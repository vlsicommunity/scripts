#!/usr/bin/env python3
"""
Disk Usage Monitor

A script to monitor multiple disks for usage limits and send email alerts
when thresholds are exceeded. Includes per-user usage breakdown.

Features:
- Parallel directory size calculation for faster execution
- Disk quota support for instant results (if available)
- Configurable thresholds per disk
- Email alerts via mailx

Usage:
    python disk_monitor.py -c config.yaml
    python disk_monitor.py -c config.yaml --dry-run
"""

import argparse
import getpass
import logging
import os
import pwd
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip install pyyaml")
    sys.exit(1)


class DiskMonitor:
    """Main class for monitoring disk usage and sending alerts."""
    
    def __init__(self, config_path: str, dry_run: bool = False):
        """
        Initialize the DiskMonitor.
        
        Args:
            config_path: Path to the YAML configuration file
            dry_run: If True, send email only to the current user
        """
        self.config_path = config_path
        self.dry_run = dry_run
        self.config = self._load_config()
        self._setup_logging()
        
    def _load_config(self) -> dict:
        """Load and validate the YAML configuration file."""
        if not os.path.exists(self.config_path):
            print(f"ERROR: Configuration file not found: {self.config_path}")
            sys.exit(1)
            
        with open(self.config_path, 'r') as f:
            try:
                config = yaml.safe_load(f)
            except yaml.YAMLError as e:
                print(f"ERROR: Failed to parse configuration file: {e}")
                sys.exit(1)
        
        # Validate required fields
        required_fields = ['email', 'disks']
        for field in required_fields:
            if field not in config:
                print(f"ERROR: Missing required configuration field: {field}")
                sys.exit(1)
        
        # Validate email configuration
        email_config = config.get('email', {})
        if 'domain' not in email_config:
            print("ERROR: Missing 'domain' in email configuration")
            sys.exit(1)
        if 'sender' not in email_config:
            print("ERROR: Missing 'sender' in email configuration")
            sys.exit(1)
            
        # Set defaults for logging
        if 'logging' not in config:
            config['logging'] = {}
        if 'file' not in config['logging']:
            config['logging']['file'] = 'disk_monitor.log'
        if 'level' not in config['logging']:
            config['logging']['level'] = 'INFO'
        
        # Set defaults for performance
        if 'performance' not in config:
            config['performance'] = {}
        if 'max_workers' not in config['performance']:
            config['performance']['max_workers'] = 8
        if 'use_quotas' not in config['performance']:
            config['performance']['use_quotas'] = True
        if 'du_timeout' not in config['performance']:
            config['performance']['du_timeout'] = 300  # 5 minutes per directory
            
        return config
    
    def _setup_logging(self) -> None:
        """Configure logging based on configuration."""
        log_config = self.config.get('logging', {})
        log_file = log_config.get('file', 'disk_monitor.log')
        log_level = log_config.get('level', 'INFO').upper()
        
        # Create log directory if needed
        log_dir = os.path.dirname(log_file)
        if log_dir and not os.path.exists(log_dir):
            try:
                os.makedirs(log_dir, exist_ok=True)
            except PermissionError:
                # Fall back to current directory
                log_file = os.path.basename(log_file)
        
        logging.basicConfig(
            level=getattr(logging, log_level, logging.INFO),
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
        self.logger.info(f"Disk Monitor started (dry_run={self.dry_run})")
        
    def get_disk_usage(self, path: str) -> Optional[Tuple[int, int, int, float]]:
        """
        Get disk usage statistics for a given path.
        
        Args:
            path: Path to check disk usage
            
        Returns:
            Tuple of (total_bytes, used_bytes, free_bytes, percent_used)
            or None if path doesn't exist
        """
        if not os.path.exists(path):
            self.logger.warning(f"Path does not exist: {path}")
            return None
            
        try:
            usage = shutil.disk_usage(path)
            total = usage.total
            used = usage.used
            free = usage.free
            percent = (used / total) * 100 if total > 0 else 0
            return (total, used, free, percent)
        except Exception as e:
            self.logger.error(f"Failed to get disk usage for {path}: {e}")
            return None
    
    def get_directory_size(self, path: str) -> int:
        """
        Get the size of a directory using 'du' command for efficiency.
        
        Args:
            path: Directory path to measure
            
        Returns:
            Size in bytes
        """
        perf_config = self.config.get('performance', {})
        timeout = perf_config.get('du_timeout', 300)
        
        try:
            # Use du -sb for accurate byte count
            result = subprocess.run(
                ['du', '-sb', path],
                capture_output=True,
                text=True,
                timeout=timeout
            )
            if result.returncode == 0:
                size_str = result.stdout.split()[0]
                return int(size_str)
            else:
                self.logger.warning(f"du command failed for {path}: {result.stderr}")
                return 0
        except subprocess.TimeoutExpired:
            self.logger.warning(f"Timeout calculating size for {path}")
            return 0
        except Exception as e:
            self.logger.error(f"Failed to get directory size for {path}: {e}")
            return 0
    
    def get_user_from_directory(self, path: str) -> Optional[str]:
        """
        Get the owner username of a directory.
        
        Args:
            path: Directory path
            
        Returns:
            Username of the directory owner or None
        """
        try:
            stat_info = os.stat(path)
            uid = stat_info.st_uid
            user_info = pwd.getpwuid(uid)
            return user_info.pw_name
        except (KeyError, OSError) as e:
            self.logger.warning(f"Could not determine owner of {path}: {e}")
            return None
    
    def _get_mount_point(self, path: str) -> str:
        """
        Get the mount point for a given path.
        
        Args:
            path: Path to find mount point for
            
        Returns:
            Mount point path
        """
        path = os.path.abspath(path)
        while not os.path.ismount(path):
            path = os.path.dirname(path)
        return path
    
    def get_user_usage_from_quota(self, disk_path: str) -> Optional[List[Dict]]:
        """
        Try to get user usage from disk quota system.
        
        This method attempts to use disk quotas for instant usage information.
        Falls back to None if quotas are not available.
        
        Args:
            disk_path: Path to the disk to analyze
            
        Returns:
            List of dicts with user info and usage, or None if quotas unavailable
        """
        perf_config = self.config.get('performance', {})
        if not perf_config.get('use_quotas', True):
            self.logger.debug("Quota usage disabled in configuration")
            return None
        
        mount_point = self._get_mount_point(disk_path)
        self.logger.debug(f"Mount point for {disk_path}: {mount_point}")
        
        # Try repquota first (requires root/sudo or proper permissions)
        user_usage = self._try_repquota(mount_point, disk_path)
        if user_usage is not None:
            return user_usage
        
        # Try individual quota commands
        user_usage = self._try_quota_per_user(disk_path)
        if user_usage is not None:
            return user_usage
        
        self.logger.info("Disk quotas not available, will use du command")
        return None
    
    def _try_repquota(self, mount_point: str, disk_path: str) -> Optional[List[Dict]]:
        """
        Try to get quota information using repquota command.
        
        Args:
            mount_point: Mount point of the filesystem
            disk_path: Original disk path for directory matching
            
        Returns:
            List of user usage dicts or None if failed
        """
        try:
            # Try repquota on the mount point
            result = subprocess.run(
                ['repquota', '-u', mount_point],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode != 0:
                self.logger.debug(f"repquota failed: {result.stderr}")
                return None
            
            # Parse repquota output
            user_usage = []
            lines = result.stdout.strip().split('\n')
            
            # Skip header lines, find data lines
            data_started = False
            for line in lines:
                # Look for the line starting with user data (after header)
                if '------' in line:
                    data_started = True
                    continue
                
                if not data_started:
                    continue
                
                # Parse user quota line
                # Format: username -- blocks soft hard grace files soft hard grace
                parts = line.split()
                if len(parts) >= 2:
                    username = parts[0].rstrip('+-')
                    if not username or username.startswith('#'):
                        continue
                    
                    # Try to get block usage (in KB)
                    try:
                        # The used blocks are typically the 2nd field after username
                        blocks_used = int(parts[1].replace('+', '').replace('-', ''))
                        size_bytes = blocks_used * 1024  # Convert KB to bytes
                        
                        # Check if user has directory under disk_path
                        user_dir = os.path.join(disk_path, username)
                        if os.path.isdir(user_dir):
                            user_usage.append({
                                'username': username,
                                'directory': user_dir,
                                'size_bytes': size_bytes,
                                'size_gb': size_bytes / (1024 ** 3),
                                'source': 'quota'
                            })
                    except (ValueError, IndexError):
                        continue
            
            if user_usage:
                self.logger.info(f"Got usage for {len(user_usage)} users from quotas")
                user_usage.sort(key=lambda x: x['size_bytes'], reverse=True)
                return user_usage
            
            return None
            
        except subprocess.TimeoutExpired:
            self.logger.debug("repquota command timed out")
            return None
        except FileNotFoundError:
            self.logger.debug("repquota command not found")
            return None
        except Exception as e:
            self.logger.debug(f"repquota failed: {e}")
            return None
    
    def _try_quota_per_user(self, disk_path: str) -> Optional[List[Dict]]:
        """
        Try to get quota information by running quota command for each user.
        
        Args:
            disk_path: Path to the disk to analyze
            
        Returns:
            List of user usage dicts or None if failed
        """
        try:
            # Get list of directories (potential users) under disk_path
            entries = os.listdir(disk_path)
        except PermissionError:
            return None
        
        user_usage = []
        quota_available = False
        
        for entry in entries:
            entry_path = os.path.join(disk_path, entry)
            if not os.path.isdir(entry_path):
                continue
            
            # Get owner of directory
            username = self.get_user_from_directory(entry_path)
            if not username:
                username = entry
            
            # Try quota command for this user
            try:
                result = subprocess.run(
                    ['quota', '-u', username, '-w'],
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                
                if result.returncode == 0 and result.stdout.strip():
                    quota_available = True
                    # Parse quota output
                    lines = result.stdout.strip().split('\n')
                    for line in lines:
                        if disk_path in line or self._get_mount_point(disk_path) in line:
                            parts = line.split()
                            if len(parts) >= 2:
                                try:
                                    # blocks used is typically first number
                                    blocks = int(parts[1].replace('*', ''))
                                    size_bytes = blocks * 1024
                                    user_usage.append({
                                        'username': username,
                                        'directory': entry_path,
                                        'size_bytes': size_bytes,
                                        'size_gb': size_bytes / (1024 ** 3),
                                        'source': 'quota'
                                    })
                                    break
                                except ValueError:
                                    continue
            except (subprocess.TimeoutExpired, FileNotFoundError):
                continue
            except Exception:
                continue
        
        if quota_available and user_usage:
            self.logger.info(f"Got usage for {len(user_usage)} users from per-user quotas")
            user_usage.sort(key=lambda x: x['size_bytes'], reverse=True)
            return user_usage
        
        return None
    
    def _calculate_optimal_workers(self, num_directories: int) -> int:
        """
        Calculate optimal number of workers based on directory count.
        
        Strategy for I/O-bound tasks (like du):
        - Use number of directories directly (more workers = more parallel I/O)
        - Cap at 16 (reasonable upper bound to avoid overwhelming the system)
        - Respect config max_workers as upper limit (if set to a number)
        - Minimum: 1 worker
        
        Args:
            num_directories: Number of directories to process
            
        Returns:
            Optimal number of workers
        """
        perf_config = self.config.get('performance', {})
        config_max = perf_config.get('max_workers')
        
        # Apply bounds
        min_workers = 1
        max_upper_bound = 16  # Hard cap for I/O operations
        
        # If config specifies a max (and it's a valid number), use it as upper limit
        if config_max is not None and isinstance(config_max, int) and config_max > 0:
            max_workers = min(config_max, max_upper_bound)
        else:
            # 'auto' or not set - use hard cap
            max_workers = max_upper_bound
        
        # For I/O-bound tasks, use as many workers as directories (up to max)
        result = max(min_workers, min(num_directories, max_workers))
        
        self.logger.debug(f"Worker calculation: dirs={num_directories}, "
                         f"config_max={config_max}, result={result}")
        
        return result
    
    def get_user_usage_parallel(self, disk_path: str) -> List[Dict]:
        """
        Calculate disk usage for each user using parallel du commands.
        
        This is significantly faster than sequential execution for multiple directories.
        The number of workers is automatically calculated based on:
        - Number of directories to process
        - Number of CPU cores
        - Config max_workers (as optional upper limit)
        
        Args:
            disk_path: Path to the disk to analyze
            
        Returns:
            List of dicts with user info and usage
        """
        if not os.path.exists(disk_path):
            self.logger.warning(f"Disk path does not exist: {disk_path}")
            return []
        
        try:
            entries = os.listdir(disk_path)
        except PermissionError:
            self.logger.error(f"Permission denied accessing: {disk_path}")
            return []
        
        # Collect directories to process
        directories = []
        for entry in entries:
            entry_path = os.path.join(disk_path, entry)
            if os.path.isdir(entry_path):
                username = self.get_user_from_directory(entry_path)
                if not username:
                    username = entry
                directories.append((entry_path, username))
        
        if not directories:
            self.logger.warning("No directories found to process")
            return []
        
        # Auto-calculate optimal number of workers
        num_workers = self._calculate_optimal_workers(len(directories))
        
        self.logger.info(f"Calculating sizes for {len(directories)} directories using {num_workers} workers (auto-calculated)")
        
        user_usage = []
        
        # Process directories in parallel
        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            # Submit all tasks
            future_to_dir = {
                executor.submit(self.get_directory_size, dir_path): (dir_path, username)
                for dir_path, username in directories
            }
            
            # Collect results as they complete
            completed = 0
            for future in as_completed(future_to_dir):
                dir_path, username = future_to_dir[future]
                completed += 1
                
                try:
                    size_bytes = future.result()
                    user_usage.append({
                        'username': username,
                        'directory': dir_path,
                        'size_bytes': size_bytes,
                        'size_gb': size_bytes / (1024 ** 3),
                        'source': 'du'
                    })
                    
                    if completed % 10 == 0:
                        self.logger.debug(f"Progress: {completed}/{len(directories)} directories processed")
                        
                except Exception as e:
                    self.logger.error(f"Error processing {dir_path}: {e}")
                    user_usage.append({
                        'username': username,
                        'directory': dir_path,
                        'size_bytes': 0,
                        'size_gb': 0,
                        'source': 'error'
                    })
        
        # Sort by size (largest first)
        user_usage.sort(key=lambda x: x['size_bytes'], reverse=True)
        
        self.logger.info(f"Completed size calculation for {len(user_usage)} directories")
        return user_usage
    
    def get_user_usage(self, disk_path: str) -> List[Dict]:
        """
        Calculate disk usage for each user (directory) under the disk path.
        
        This method first tries to use disk quotas for instant results.
        If quotas are unavailable, it falls back to parallel du execution.
        
        Args:
            disk_path: Path to the disk to analyze
            
        Returns:
            List of dicts with user info and usage
        """
        # Try quota-based approach first (instant results)
        self.logger.info("Attempting to get usage from disk quotas...")
        user_usage = self.get_user_usage_from_quota(disk_path)
        
        if user_usage is not None:
            self.logger.info(f"Successfully retrieved usage from quotas for {len(user_usage)} users")
            return user_usage
        
        # Fall back to parallel du execution
        self.logger.info("Falling back to parallel du calculation...")
        return self.get_user_usage_parallel(disk_path)
    
    def bytes_to_gb(self, bytes_val: int) -> float:
        """Convert bytes to gigabytes."""
        return bytes_val / (1024 ** 3)
    
    def format_size_gb(self, gb_val: float) -> str:
        """Format size in GB with 2 decimal places."""
        return f"{gb_val:.2f} GB"
    
    def generate_alert_email(self, disk_config: dict, usage_stats: tuple, 
                            user_usage: List[Dict]) -> Tuple[str, str]:
        """
        Generate the alert email subject and body.
        
        Args:
            disk_config: Configuration for the disk
            usage_stats: Tuple of (total, used, free, percent)
            user_usage: List of user usage information
            
        Returns:
            Tuple of (subject, body)
        """
        total, used, free, percent = usage_stats
        disk_name = disk_config.get('name', disk_config['path'])
        threshold = disk_config.get('usage_limit_percent', 80)
        
        subject = f"[ALERT] Disk Usage Critical: {disk_name} ({percent:.1f}% used)"
        
        # Determine data source
        data_source = "quota" if user_usage and user_usage[0].get('source') == 'quota' else "du"
        
        # Prepare user data and calculate column widths
        user_data = []
        for user in user_usage:
            dir_name = os.path.basename(user['directory'].rstrip('/'))
            owner = user['username']
            size_str = self.format_size_gb(user['size_gb'])
            user_data.append((dir_name, owner, size_str))
        
        # Calculate max widths for dynamic alignment
        min_dir_width = len("Directory")
        min_owner_width = len("Owner")
        min_size_width = len("Size")
        
        if user_data:
            max_dir_width = max(min_dir_width, max(len(d[0]) for d in user_data))
            max_owner_width = max(min_owner_width, max(len(d[1]) for d in user_data))
            max_size_width = max(min_size_width, max(len(d[2]) for d in user_data))
        else:
            max_dir_width = min_dir_width
            max_owner_width = min_owner_width
            max_size_width = min_size_width
        
        # Add padding between columns (4 spaces)
        col_gap = "    "
        
        # Build email body
        body_lines = [
            "=" * 55,
            "DISK USAGE ALERT",
            "=" * 55,
            "",
            f"Disk Name:  {disk_name}",
            f"Path:       {disk_config['path']}",
            f"Usage:      {percent:.1f}% ({self.format_size_gb(self.bytes_to_gb(used))} / {self.format_size_gb(self.bytes_to_gb(total))})",
            f"Free:       {self.format_size_gb(self.bytes_to_gb(free))}",
            f"Threshold:  {threshold}%",
            "",
            "-" * 55,
            f"USER USAGE BREAKDOWN (source: {data_source})",
            "-" * 55,
            "",
            # Dynamically aligned header
            f"{'Directory':<{max_dir_width}}{col_gap}{'Owner':<{max_owner_width}}{col_gap}{'Size':>{max_size_width}}",
            f"{'-' * max_dir_width}{col_gap}{'-' * max_owner_width}{col_gap}{'-' * max_size_width}",
        ]
        
        # Add user data with dynamic alignment
        for dir_name, owner, size_str in user_data:
            body_lines.append(
                f"{dir_name:<{max_dir_width}}{col_gap}{owner:<{max_owner_width}}{col_gap}{size_str:>{max_size_width}}"
            )
        
        body_lines.extend([
            "",
            "-" * 55,
            "",
            "ACTION REQUIRED: Please clean up unnecessary files.",
            "",
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            "=" * 55,
        ])
        
        body = "\n".join(body_lines)
        return subject, body
    
    def get_recipient_list(self, user_usage: List[Dict]) -> List[str]:
        """
        Build the list of email recipients.
        
        Args:
            user_usage: List of user usage information
            
        Returns:
            List of email addresses
        """
        email_config = self.config.get('email', {})
        domain = email_config.get('domain', 'company.com')
        # Use 'or []' to handle None values (when administrators is null in YAML)
        administrators = email_config.get('administrators') or []
        
        recipients = set()
        
        # Add administrators
        for admin in administrators:
            recipients.add(admin)
        
        # Add users based on directory ownership
        for user in user_usage:
            username = user['username']
            if username:
                user_email = f"{username}@{domain}"
                recipients.add(user_email)
        
        return list(recipients)
    
    def send_email(self, subject: str, body: str, recipients: List[str]) -> bool:
        """
        Send email using the mailx command.
        
        Args:
            subject: Email subject
            body: Email body
            recipients: List of recipient email addresses
            
        Returns:
            True if email was sent successfully, False otherwise
        """
        if not recipients:
            self.logger.warning("No recipients specified, skipping email")
            return False
        
        email_config = self.config.get('email', {})
        sender = email_config.get('sender', 'disk-monitor@localhost')
        
        # In dry-run mode, send only to the current user
        if self.dry_run:
            current_user = getpass.getuser()
            domain = email_config.get('domain', 'company.com')
            recipients = [f"{current_user}@{domain}"]
            subject = f"[DRY-RUN] {subject}"
            self.logger.info(f"Dry-run mode: sending email only to {recipients[0]}")
        
        recipient_str = ' '.join(recipients)
        
        # Build mailx command - use a temp file to avoid shell escaping issues
        import tempfile
        try:
            with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as f:
                f.write(body)
                temp_file = f.name
            
            cmd = f"cat '{temp_file}' | mailx -r '{sender}' -s \"{subject}\" {recipient_str}"
            
            self.logger.info(f"Sending email to {len(recipients)} recipient(s)")
            self.logger.debug(f"Recipients: {recipients}")
            self.logger.debug(f"Email command: {cmd}")
            
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=60
            )
            
            # Clean up temp file
            os.unlink(temp_file)
            
            if result.returncode == 0:
                self.logger.info("Email sent successfully")
                if result.stdout:
                    self.logger.debug(f"mailx stdout: {result.stdout}")
                if result.stderr:
                    self.logger.debug(f"mailx stderr: {result.stderr}")
                return True
            else:
                self.logger.error(f"Failed to send email: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            self.logger.error("Timeout while sending email")
            return False
        except Exception as e:
            self.logger.error(f"Error sending email: {e}")
            return False
    
    def check_disk(self, disk_config: dict) -> bool:
        """
        Check a single disk and send alert if threshold is exceeded.
        
        Args:
            disk_config: Configuration for the disk to check
            
        Returns:
            True if alert was sent, False otherwise
        """
        disk_path = disk_config.get('path')
        disk_name = disk_config.get('name', disk_path)
        threshold = disk_config.get('usage_limit_percent', 80)
        
        self.logger.info(f"Checking disk: {disk_name} ({disk_path})")
        
        # Get disk usage
        usage_stats = self.get_disk_usage(disk_path)
        if not usage_stats:
            self.logger.error(f"Could not get usage for disk: {disk_path}")
            return False
        
        total, used, free, percent = usage_stats
        self.logger.info(f"Disk usage: {percent:.1f}% (threshold: {threshold}%)")
        
        # Check if threshold exceeded
        if percent < threshold:
            self.logger.info(f"Disk usage below threshold, no alert needed")
            return False
        
        self.logger.warning(f"Disk usage EXCEEDS threshold! ({percent:.1f}% >= {threshold}%)")
        
        # Calculate per-user usage
        self.logger.info("Calculating per-user usage...")
        import time
        start_time = time.time()
        
        user_usage = self.get_user_usage(disk_path)
        
        elapsed = time.time() - start_time
        self.logger.info(f"User usage calculation completed in {elapsed:.1f} seconds")
        
        if not user_usage:
            self.logger.warning("No user directories found")
        else:
            self.logger.info(f"Found {len(user_usage)} user directories")
        
        # Generate email
        subject, body = self.generate_alert_email(disk_config, usage_stats, user_usage)
        
        # Get recipients
        recipients = self.get_recipient_list(user_usage)
        
        # Send email
        return self.send_email(subject, body, recipients)
    
    def run(self) -> int:
        """
        Run the disk monitor for all configured disks.
        
        Returns:
            Exit code (0 for success, 1 for errors)
        """
        disks = self.config.get('disks', [])
        
        if not disks:
            self.logger.warning("No disks configured to monitor")
            return 0
        
        self.logger.info(f"Monitoring {len(disks)} disk(s)")
        
        # Log performance settings
        perf_config = self.config.get('performance', {})
        self.logger.info(f"Performance settings: max_workers={perf_config.get('max_workers', 8)}, "
                        f"use_quotas={perf_config.get('use_quotas', True)}")
        
        alerts_sent = 0
        errors = 0
        
        for disk_config in disks:
            try:
                if self.check_disk(disk_config):
                    alerts_sent += 1
            except Exception as e:
                self.logger.error(f"Error checking disk {disk_config.get('path', 'unknown')}: {e}")
                errors += 1
        
        self.logger.info(f"Monitoring complete. Alerts sent: {alerts_sent}, Errors: {errors}")
        
        return 1 if errors > 0 else 0


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Monitor disk usage and send alerts when thresholds are exceeded',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s -c config.yaml
  %(prog)s -c /path/to/config.yaml --dry-run

Performance:
  The script uses disk quotas when available for instant results.
  If quotas are unavailable, it uses parallel 'du' commands for faster execution.
  Configure performance settings in the YAML config file.
        """
    )
    
    parser.add_argument(
        '-c', '--config',
        required=True,
        help='Path to YAML configuration file'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Send email only to the current user (for testing)'
    )
    
    args = parser.parse_args()
    
    monitor = DiskMonitor(args.config, args.dry_run)
    sys.exit(monitor.run())


if __name__ == '__main__':
    main()
