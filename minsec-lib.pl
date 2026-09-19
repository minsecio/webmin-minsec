package minsec;

use strict;
use warnings;
use Cwd qw(abs_path);
use Errno qw(EINTR);
use Fcntl qw(:DEFAULT :flock);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir tempfile);
use IO::Select;
use IO::Socket::UNIX;
use IO::Handle;
use IPC::Open3;
use JSON::PP;
use POSIX qw(strftime);
use Socket qw(AF_INET AF_INET6 SOCK_STREAM inet_pton);
use Symbol qw(gensym);
use Time::HiRes qw(time);

our (%config, %access, %text, %in, $module_name, $module_root_directory);

BEGIN {
	if (!$ENV{'MINSEC_TESTING'}) {
		my @webmin_roots;
		push(@webmin_roots, $ENV{'SERVER_ROOT'}) if ($ENV{'SERVER_ROOT'});
		if ($ENV{'SCRIPT_FILENAME'}) {
			my $script_directory = dirname($ENV{'SCRIPT_FILENAME'});
			push(@webmin_roots, dirname($script_directory));
		}
		push(@webmin_roots, '/usr/libexec/webmin', '/usr/share/webmin');
		my %seen_root;
		foreach my $root (@webmin_roots) {
			next if (!$root || $seen_root{$root}++ || !-r File::Spec->catfile($root, 'WebminCore.pm'));
			unshift(@INC, $root);
			last;
		}
		require WebminCore;
		{
			package main;
			WebminCore->import();
			init_config();
			%main::access = get_module_acl();
		}
		{
			package minsec;
			WebminCore->import();
		}
		*config = \%main::config;
		*access = \%main::access;
		*text = \%main::text;
		*in = \%main::in;
		$module_name = $main::module_name;
		$module_root_directory = $main::module_root_directory;
	}
}

my $JSON = JSON::PP->new->utf8->canonical->allow_nonref(0);

sub acl_permissions
{
	return qw(view events nftables bans filters config raw service boot);
}

sub navigation
{
	my ($selected) = @_;
	my @tabs = (
		[ 'dashboard', $text{'index_dashboard'}, 'index.cgi' ],
		[ 'bans', $text{'index_bans'}, 'bans.cgi' ],
		[ 'filters', $text{'index_filters'}, 'filters.cgi' ],
		[ 'config', $text{'index_config'}, 'config.cgi' ],
		[ 'files', $text{'index_files'}, 'files.cgi' ],
		[ 'events', $text{'index_events'}, 'events.cgi' ],
		[ 'nftables', $text{'index_nftables'}, 'nftables.cgi' ],
	);
	my @links = map {
		$_->[0] eq $selected ? '<b>'.html_escape($_->[1]).'</b>'
					  : link_html($_->[2], $_->[1])
		} @tabs;
	return main::ui_links_row(\@links);
}

sub check_acl
{
	my ($permission) = @_;
	return $access{$permission} ? 1 : 0;
}

sub require_acl
{
	my ($permission) = @_;
	return 1 if (check_acl($permission));
	main::error($text{'acl_ecannot'} || 'Access denied');
	return 0;
}

sub require_post
{
	my $method = $ENV{'REQUEST_METHOD'} || '';
	return 1 if ($method eq 'POST');
	main::error($text{'error_post'} || 'POST required');
	return 0;
}

sub settings
{
	return {
		'minsec_cmd' => $config{'minsec_cmd'} || '/usr/bin/minsec',
		'config_dir' => $config{'config_dir'} || '/etc/minsec',
		'service_name' => $config{'service_name'} || 'minsec',
		'nft_cmd' => $config{'nft_cmd'} || '/usr/sbin/nft',
		'perpage' => _positive_int($config{'perpage'}, 50, 500),
		'connect_timeout' => _positive_int($config{'connect_timeout'}, 3, 30),
		'read_timeout' => _positive_int($config{'read_timeout'}, 5, 60),
	};
}

sub _positive_int
{
	my ($value, $default, $maximum) = @_;
	return $default if (!defined($value) || $value !~ /^\d+$/ || !$value);
	return $maximum if ($value > $maximum);
	return int($value);
}

sub decode_json_object
{
	my ($input) = @_;
	my $decoded = eval { $JSON->decode($input) };
	return (undef, "Invalid JSON: $@") if ($@);
	return (undef, 'JSON response is not an object') if (ref($decoded) ne 'HASH');
	return ($decoded, undef);
}

sub run_json_command
{
	my ($arguments, $timeout) = @_;
	my ($stdout, $stderr, $status, $capture_error) = _run_command($arguments, $timeout);
	return (undef, $capture_error) if ($capture_error);
	my ($result, $decode_error) = decode_json_object($stdout);
	if ($decode_error) {
		my $detail = $stderr || $decode_error;
		$detail =~ s/\s+\z//;
		return (undef, $detail);
	}
	if ($status || (exists($result->{'ok'}) && !$result->{'ok'})) {
		my $structured_errors = '';
		if (ref($result->{'errors'}) eq 'ARRAY') {
			$structured_errors = join('; ', map {
				my $item = $_;
				ref($item) eq 'HASH' ?
					(($item->{'filter'} ? 'filter '.$item->{'filter'}.': ' : '').($item->{'error'} || 'error')) :
					$item
			} @{$result->{'errors'}});
		}
		my $message = $result->{'error'} || $result->{'message'} || $structured_errors || $stderr || "Command exited with status $status";
		$message =~ s/\s+\z//;
		return ($result, $message);
	}
	return ($result, undef);
}

sub _run_command
{
	my ($arguments, $timeout) = @_;
	return (undef, undef, undef, 'Command must be an argument list') if (ref($arguments) ne 'ARRAY' || !@$arguments);
	$timeout ||= 15;
	my ($input_handle, $output_handle, $error_handle);
	$error_handle = gensym();
	my $pid = eval { open3($input_handle, $output_handle, $error_handle, @$arguments) };
	return (undef, undef, undef, "Failed to execute command: $@") if ($@);
	close($input_handle);
	my $stdout_fd = fileno($output_handle);
	my $stderr_fd = fileno($error_handle);
	my $selector = IO::Select->new($output_handle, $error_handle);
	my %buffers = ($stdout_fd => '', $stderr_fd => '');
	my $deadline = time() + $timeout;
	while ($selector->count()) {
		my $remaining = $deadline - time();
		if ($remaining <= 0) {
			kill('TERM', $pid);
			waitpid($pid, 0);
			return (undef, undef, undef, 'Command timed out');
		}
		my @ready = $selector->can_read($remaining);
		if (!@ready) {
			kill('TERM', $pid);
			waitpid($pid, 0);
			return (undef, undef, undef, 'Command timed out');
		}
		foreach my $handle (@ready) {
			my $read = sysread($handle, my $chunk, 8192);
			if (!defined($read)) {
				next if ($! == EINTR);
				$selector->remove($handle);
				next;
			}
			if (!$read) {
				$selector->remove($handle);
				close($handle);
				next;
			}
			$buffers{fileno($handle)} .= $chunk;
			if (length($buffers{$stdout_fd}) + length($buffers{$stderr_fd}) > 10 * 1024 * 1024) {
				kill('TERM', $pid);
				waitpid($pid, 0);
				return (undef, undef, undef, 'Command output is too large');
			}
		}
	}
	waitpid($pid, 0);
	my $status = $? >> 8;
	return ($buffers{$stdout_fd} || '', $buffers{$stderr_fd} || '', $status, undef);
}

sub inspect
{
	my ($config_dir) = @_;
	my $settings = settings();
	$config_dir ||= $settings->{'config_dir'};
	my @command = ($settings->{'minsec_cmd'}, '--config-dir', $config_dir, '--json', 'inspect');
	my ($result, $error) = run_json_command(\@command, 15);
	return ($result, $error) if ($error);
	return (undef, 'Unsupported inspection schema') if (($result->{'schema_version'} || 0) != 1);
	return ($result, undef);
}

sub check_config
{
	my ($config_dir) = @_;
	my $settings = settings();
	$config_dir ||= $settings->{'config_dir'};
	my @command = ($settings->{'minsec_cmd'}, '--config-dir', $config_dir, '--json', 'check', '--all');
	return run_json_command(\@command, 30);
}

sub read_events
{
	my ($limit) = @_;
	$limit = _positive_int($limit, settings()->{'perpage'}, 1000);
	my @command = (settings()->{'minsec_cmd'}, '--json', 'events', '--last', $limit);
	my ($stdout, $stderr, $status, $capture_error) = _run_command(\@command, 15);
	return (undef, $capture_error) if ($capture_error);
	if ($status) {
		$stderr =~ s/\s+\z//;
		return (undef, $stderr || "Events command exited with status $status");
	}
	my @events;
	foreach my $line (split(/\r?\n/, $stdout)) {
		next if ($line =~ /^\s*$/);
		my ($event, $decode_error) = decode_json_object($line);
		return (undef, $decode_error) if ($decode_error);
		push(@events, $event);
		return (undef, 'Events command returned too many records') if (@events > $limit);
	}
	return (\@events, undef);
}

sub test_filter
{
	my ($filter, $log_file) = @_;
	return (undef, 'Invalid filter name') if (!defined($filter) || $filter !~ /\A[A-Za-z0-9_.-]+\z/);
	return (undef, 'Log file must be an absolute path') if (!defined($log_file) || !File::Spec->file_name_is_absolute($log_file));
	return (undef, 'Log file is not a readable regular file') if (!-f $log_file || !-r _ || -l $log_file);
	my @command = (settings()->{'minsec_cmd'}, '--json', 'test', $filter, $log_file, '--quiet');
	return run_json_command(\@command, 30);
}

sub socket_command
{
	my ($socket_path, $request, $options) = @_;
	$options ||= {};
	return (undef, 'Socket path is missing') if (!defined($socket_path) || $socket_path eq '');
	return (undef, 'Socket request must be an object') if (ref($request) ne 'HASH');
	my $settings = settings();
	my $connect_timeout = $options->{'connect_timeout'} || $settings->{'connect_timeout'};
	my $read_timeout = $options->{'read_timeout'} || $settings->{'read_timeout'};
	my $socket = IO::Socket::UNIX->new(
		'Type' => SOCK_STREAM,
		'Peer' => $socket_path,
		'Timeout' => $connect_timeout,
	);
	return (undef, "Cannot connect to minsec socket: $!") if (!$socket);
	my $line = $JSON->encode($request)."\n";
	my $offset = 0;
	while ($offset < length($line)) {
		my $written = syswrite($socket, $line, length($line) - $offset, $offset);
		return (undef, "Cannot write to minsec socket: $!") if (!defined($written));
		$offset += $written;
	}
	my $selector = IO::Select->new($socket);
	my $deadline = time() + $read_timeout;
	my $response = '';
	while (index($response, "\n") < 0) {
		my $remaining = $deadline - time();
		return (undef, 'Minsec socket read timed out') if ($remaining <= 0);
		return (undef, 'Minsec socket read timed out') if (!$selector->can_read($remaining));
		my $read = sysread($socket, my $chunk, 8192);
		return (undef, "Cannot read minsec socket: $!") if (!defined($read));
		return (undef, 'Minsec socket closed without a response') if (!$read);
		$response .= $chunk;
		return (undef, 'Minsec socket response is too large') if (length($response) > 1024 * 1024);
	}
	close($socket);
	$response =~ s/\n.*\z//s;
	my ($decoded, $error) = decode_json_object($response);
	return (undef, $error) if ($error);
	if (exists($decoded->{'ok'}) && !$decoded->{'ok'}) {
		return ($decoded, $decoded->{'error'} || 'Minsec rejected the request');
	}
	return ($decoded, undef);
}

sub inspection_path
{
	my ($inspection, $name) = @_;
	return if (ref($inspection) ne 'HASH');
	my $paths = $inspection->{'paths'};
	return if (ref($paths) ne 'HASH');
	return $paths->{$name};
}

sub control_request
{
	my ($request, $inspection) = @_;
	if (!$inspection) {
		my $error;
		($inspection, $error) = inspect();
		return (undef, $error) if ($error);
	}
	my $socket = inspection_path($inspection, 'control_socket');
	return socket_command($socket, $request);
}

sub validate_duration
{
	my ($value, $allow_empty) = @_;
	return (undef, undef) if ($allow_empty && (!defined($value) || $value eq ''));
	return (undef, 'Duration is required') if (!defined($value) || $value eq '');
	return (int($value), undef) if ($value =~ /^\d+$/);
	my %units = ('s' => 1, 'm' => 60, 'h' => 3600, 'd' => 86400, 'w' => 604800);
	return (undef, 'Invalid duration') if ($value !~ /\A(\d+)([smhdw])\z/i);
	my $seconds = $1 * $units{lc($2)};
	return (undef, 'Duration is too large') if ($seconds > 315360000);
	return ($seconds, undef);
}

sub format_duration
{
	my ($seconds) = @_;
	return '-' if (!defined($seconds));
	$seconds = int($seconds);
	return '0s' if ($seconds <= 0);
	my @parts;
	foreach my $unit ([86400, 'd'], [3600, 'h'], [60, 'm'], [1, 's']) {
		my $amount = int($seconds / $unit->[0]);
		next if (!$amount);
		push(@parts, $amount.$unit->[1]);
		$seconds %= $unit->[0];
	}
	return join(' ', @parts);
}

sub validate_network
{
	my ($value) = @_;
	return (undef, 'Address or network is required') if (!defined($value) || $value eq '');
	return (undef, 'Address contains whitespace') if ($value =~ /\s/);
	my ($address, $prefix) = split('/', $value, 2);
	my $family = index($address, ':') >= 0 ? AF_INET6 : AF_INET;
	my $packed = eval { inet_pton($family, $address) };
	return (undef, 'Invalid IP address') if (!$packed);
	my $maximum = $family == AF_INET6 ? 128 : 32;
	if (defined($prefix)) {
		return (undef, 'Invalid network prefix') if ($prefix !~ /^\d+$/ || $prefix > $maximum);
	}
	else {
		$prefix = $maximum;
	}
	return ($address.'/'.$prefix, undef);
}

sub validate_filename
{
	my ($name, $kind) = @_;
	return (undef, 'Filename is required') if (!defined($name) || $name eq '');
	return (undef, 'Unsafe filename') if ($name =~ /[\\\/\0]/ || $name =~ /^\./ || $name =~ /\.\./);
	my $suffix = $kind && $kind eq 'filter' ? '.toml' : '.toml';
	return (undef, 'Filename must end in .toml') if ($name !~ /\Q$suffix\E\z/);
	return (undef, 'Unsafe filename') if ($name !~ /\A[A-Za-z0-9][A-Za-z0-9_.-]*\.toml\z/);
	return ($name, undef);
}

sub paginate
{
	my ($items, $page, $per_page) = @_;
	$items = [] if (ref($items) ne 'ARRAY');
	$page = 1 if (!defined($page) || $page !~ /^\d+$/ || $page < 1);
	$per_page = _positive_int($per_page, settings()->{'perpage'}, 500);
	my $total = scalar(@$items);
	my $pages = $total ? int(($total + $per_page - 1) / $per_page) : 1;
	$page = $pages if ($page > $pages);
	my $start = ($page - 1) * $per_page;
	my $end = $start + $per_page - 1;
	$end = $total - 1 if ($end >= $total);
	my @slice = $total ? @$items[$start .. $end] : ();
	return (\@slice, {'page' => $page, 'pages' => $pages, 'total' => $total});
}

sub service_state
{
	my $service = settings()->{'service_name'};
	my $loaded = eval { main::foreign_require('init', 'init-lib.pl'); 1 };
	return {'running' => 0, 'boot' => 0, 'known' => 0} if (!$loaded);
	my $status = init::action_status($service);
	return map_service_state($status);
}

sub map_service_state
{
	my ($status) = @_;
	return {
		'running' => $status == 2 ? 1 : 0,
		'boot' => $status > 0 ? 1 : 0,
		'known' => $status >= 0 ? 1 : 0,
		'raw' => $status,
	};
}

sub service_action
{
	my ($action) = @_;
	my %allowed = map { $_ => 1 } qw(start stop restart enable disable);
	return (undef, 'Invalid service action') if (!$allowed{$action});
	my $loaded = eval { main::foreign_require('init', 'init-lib.pl'); 1 };
	return (undef, 'Webmin init module is unavailable') if (!$loaded);
	my $service = settings()->{'service_name'};
	if ($action eq 'enable') {
		init::enable_at_boot($service);
		return (1, undef);
	}
	if ($action eq 'disable') {
		init::disable_at_boot($service);
		return (1, undef);
	}
	my ($ok, $error);
	if ($action eq 'start') {
		($ok, $error) = init::start_action($service);
	}
	elsif ($action eq 'stop') {
		($ok, $error) = init::stop_action($service);
	}
	else {
		($ok, $error) = init::restart_action($service);
	}
	return ($ok, $ok ? undef : ($error || "Unable to $action service"));
}

sub discovered_files
{
	my ($inspection) = @_;
	my @files;
	my $discovered = $inspection->{'files'} || {};
	foreach my $key (qw(main dropins custom_filters)) {
		my $value = $discovered->{$key};
		if (ref($value) eq 'ARRAY') {
			push(@files, @$value);
		}
		elsif (defined($value) && !ref($value)) {
			push(@files, $value);
		}
	}
	my %seen;
	return grep { defined($_) && !$seen{$_}++ } @files;
}

sub discovered_file_kind
{
	my ($inspection, $path) = @_;
	return 'dropin' if (ref($inspection) ne 'HASH' || !defined($path));
	my $files = $inspection->{'files'} || {};
	my $canonical = File::Spec->canonpath($path);
	my $main = $files->{'main'};
	return 'main' if (defined($main) && !ref($main) &&
		File::Spec->canonpath($main) eq $canonical);
	foreach my $custom (@{$files->{'custom_filters'} || []}) {
		return 'filter' if (defined($custom) &&
			File::Spec->canonpath($custom) eq $canonical);
	}
	return 'dropin';
}

sub main_config_file
{
	my ($inspection) = @_;
	return if (ref($inspection) ne 'HASH' || ref($inspection->{'files'}) ne 'HASH');
	return $inspection->{'files'}->{'main'};
}

sub allowed_file_path
{
	my ($path, $inspection, $for_create, $kind) = @_;
	return (undef, 'Path is required') if (!defined($path) || $path eq '');
	my $config_dir = inspection_path($inspection, 'config_dir') || settings()->{'config_dir'};
	my %discovered = map { File::Spec->canonpath($_) => 1 } discovered_files($inspection);
	my $canonical_path = File::Spec->canonpath($path);
	return (undef, 'Path was not discovered by minsec') if (!$for_create && !$discovered{$canonical_path});
	my $resolved_config = abs_path($config_dir);
	return (undef, 'Configuration directory is unavailable') if (!$resolved_config);
	my $parent = dirname($canonical_path);
	my $resolved_parent = abs_path($parent);
	return (undef, 'Configuration parent directory is unavailable') if (!$resolved_parent);
	return (undef, 'Path is outside the editable configuration tree')
		if ($resolved_parent ne $resolved_config && index($resolved_parent, $resolved_config.'/') != 0);
	return (undef, 'Refusing to edit a symbolic link') if (-l $canonical_path);
	return ($canonical_path, undef) if (!$for_create);
	my $subdir = $kind && $kind eq 'filter' ? 'filters' : 'conf.d';
	my ($name, $name_error) = validate_filename(basename($path), $kind);
	return (undef, $name_error) if ($name_error);
	my $expected = File::Spec->catfile($config_dir, $subdir, $name);
	return (undef, 'Path is outside the editable configuration tree') if (File::Spec->canonpath($path) ne File::Spec->canonpath($expected));
	$parent = dirname($expected);
	$resolved_parent = abs_path($parent);
	return (undef, 'Configuration directory is unavailable') if (!$resolved_parent || !$resolved_config);
	return (undef, 'Unsafe configuration directory') if (index($resolved_parent, $resolved_config.'/') != 0);
	return (undef, 'Refusing to edit a symbolic link') if (-l $expected);
	return ($expected, undef);
}

sub copy_tree
{
	my ($source, $destination) = @_;
	return 'Configuration directory does not exist' if (!-d $source);
	make_path($destination, {'mode' => 0700});
	my $error;
	find({
		'no_chdir' => 1,
		'wanted' => sub {
			return if ($error);
			my $relative = File::Spec->abs2rel($File::Find::name, $source);
			return if ($relative eq '.');
			my $target = File::Spec->catfile($destination, $relative);
			if (-l $File::Find::name) {
				$error = "Refusing symbolic link $relative";
			}
			elsif (-d _) {
				make_path($target, {'mode' => 0700});
			}
			elsif (-f _) {
				make_path(dirname($target), {'mode' => 0700});
				copy($File::Find::name, $target) || ($error = "Cannot copy $relative: $!");
			}
		},
	}, $source);
	return $error;
}

sub atomic_write
{
	my ($path, $content, $mode) = @_;
	$mode ||= 0640;
	make_path(dirname($path), {'mode' => 0750});
	sysopen(my $lock, $path.'.lock', O_RDWR | O_CREAT, 0600) || return "Cannot open lock: $!";
	flock($lock, LOCK_EX) || return "Cannot lock file: $!";
	my ($handle, $temporary) = tempfile('.minsec.XXXXXX', 'DIR' => dirname($path), 'UNLINK' => 0);
	binmode($handle);
	print {$handle} $content || return "Cannot write temporary file: $!";
	$handle->flush() || return "Cannot flush temporary file: $!";
	chmod($mode, $temporary) || return "Cannot set file permissions: $!";
	close($handle) || return "Cannot close temporary file: $!";
	rename($temporary, $path) || return "Cannot replace configuration: $!";
	close($lock);
	return;
}

sub staged_change
{
	my (%options) = @_;
	my $config_dir = $options{'config_dir'} || settings()->{'config_dir'};
	my $live_path = $options{'path'};
	return (undef, 'Live path is required') if (!$live_path);
	my $temporary_root = tempdir('minsec-webmin-XXXXXX', 'TMPDIR' => 1, 'CLEANUP' => 1);
	my $staged_dir = File::Spec->catdir($temporary_root, 'config');
	my $copy_error = copy_tree($config_dir, $staged_dir);
	return (undef, $copy_error) if ($copy_error);
	my $relative = File::Spec->abs2rel($live_path, $config_dir);
	return (undef, 'Path is outside the configuration directory') if ($relative =~ /^\.\./);
	my $staged_path = File::Spec->catfile($staged_dir, $relative);
	if ($options{'delete'}) {
		return (undef, 'File does not exist') if (!-f $staged_path);
		unlink($staged_path) || return (undef, "Cannot stage deletion: $!");
	}
	else {
		my $write_error = atomic_write($staged_path, $options{'content'} // '', $options{'mode'} || 0640);
		return (undef, $write_error) if ($write_error);
	}
	my ($validation, $validation_error);
	if ($options{'validator'}) {
		($validation, $validation_error) = $options{'validator'}->($staged_dir);
	}
	else {
		($validation, $validation_error) = check_config($staged_dir);
	}
	return ($validation, $validation_error) if ($validation_error || !$validation || !$validation->{'ok'});
	if ($options{'delete'}) {
		sysopen(my $lock, $live_path.'.lock', O_RDWR | O_CREAT, 0600) || return (undef, "Cannot open lock: $!");
		flock($lock, LOCK_EX) || return (undef, "Cannot lock file: $!");
		unlink($live_path) || return (undef, "Cannot delete configuration: $!");
		close($lock);
	}
	else {
		my $write_error = atomic_write($live_path, $options{'content'} // '', $options{'mode'} || 0640);
		return (undef, $write_error) if ($write_error);
	}
	return ($validation, undef);
}

sub toml_quote
{
	my ($value) = @_;
	$value = '' if (!defined($value));
	$value =~ s/\\/\\\\/g;
	$value =~ s/"/\\"/g;
	$value =~ s/\n/\\n/g;
	$value =~ s/\r/\\r/g;
	$value =~ s/\t/\\t/g;
	return '"'.$value.'"';
}

sub render_webmin_toml
{
	my ($values) = @_;
	$values ||= {};
	my %render_values = %$values;
	my %defaults = ref($values->{'defaults'}) eq 'HASH' ? %{$values->{'defaults'}} : ();
	$defaults{'allow'} = $values->{'allowlist'} if (ref($values->{'allowlist'}) eq 'ARRAY');
	$render_values{'defaults'} = \%defaults;
	my @lines = ('# Managed by Webmin. Other minsec configuration files are preserved.', '');
	foreach my $section (qw(defaults paths)) {
		my $section_values = $render_values{$section};
		next if (ref($section_values) ne 'HASH' || !keys(%$section_values));
		push(@lines, '['.$section.']');
		foreach my $key (sort(keys(%$section_values))) {
			my $value = $section_values->{$key};
			next if (!defined($value) || $value eq '');
			my $encoded;
			if (ref($value) eq 'ARRAY') {
				$encoded = '['.join(', ', map { toml_quote($_) } @$value).']';
			}
			else {
				$encoded = $value =~ /\A(?:true|false|-?\d+(?:\.\d+)?)\z/ ? $value : toml_quote($value);
			}
			push(@lines, $key.' = '.$encoded);
		}
		push(@lines, '');
	}
	my $escalate = $render_values{'escalate'};
	if (ref($escalate) eq 'HASH' && keys(%$escalate)) {
		push(@lines, '[defaults.escalate]');
		foreach my $key (sort(keys(%$escalate))) {
			my $value = $escalate->{$key};
			next if (!defined($value) || $value eq '');
			my $encoded = $value =~ /\A(?:true|false|-?\d+(?:\.\d+)?)\z/ ? $value : toml_quote($value);
			push(@lines, $key.' = '.$encoded);
		}
		push(@lines, '');
	}
	my $filters = $values->{'filters'};
	if (ref($filters) eq 'HASH') {
		foreach my $name (sort(keys(%$filters))) {
			next if ($name !~ /\A[A-Za-z0-9_.-]+\z/);
			push(@lines, '[filters.'.toml_quote($name).']');
			foreach my $key (sort(keys(%{$filters->{$name}}))) {
				my $value = $filters->{$name}->{$key};
				next if (!defined($value) || $value eq '');
				my $encoded = $value =~ /\A(?:true|false|-?\d+(?:\.\d+)?)\z/ ? $value : toml_quote($value);
				push(@lines, $key.' = '.$encoded);
			}
			push(@lines, '');
		}
	}
	return join("\n", @lines)."\n";
}

sub nftables_state
{
	my @command = (settings()->{'nft_cmd'}, '-j', 'list', 'table', 'inet', 'minsec');
	my ($result, $error) = run_json_command(\@command, 15);
	return (undef, $error) if ($error);
	my $objects = $result->{'nftables'};
	return (undef, 'Nftables result is malformed') if (ref($objects) ne 'ARRAY');
	my $view = {'chains' => [], 'sets' => [], 'counters' => []};
	foreach my $entry (@$objects) {
		next if (ref($entry) ne 'HASH');
		foreach my $type (qw(chain set counter)) {
			next if (ref($entry->{$type}) ne 'HASH');
			my $object = $entry->{$type};
			next if (($object->{'family'} || '') ne 'inet' || ($object->{'table'} || '') ne 'minsec');
			if ($type eq 'set') {
				next if (($object->{'name'} || '') !~ /\A(?:ban4|ban6|allow4|allow6)\z/);
				push(@{$view->{'sets'}}, $object);
			}
			elsif ($type eq 'chain') {
				push(@{$view->{'chains'}}, $object);
			}
			else {
				push(@{$view->{'counters'}}, $object);
			}
		}
	}
	return ($view, undef);
}

sub action_button
{
	my ($label, $name, $value) = @_;
	return '<button class="ui_submit" type="submit" name="'.html_escape($name).
		'" value="'.html_escape($value).'">'.html_escape($label).'</button>';
}

sub link_html
{
	my ($url, $label) = @_;
	return '<a href="'.html_escape($url).'">'.html_escape($label).'</a>';
}

sub format_timestamp
{
	my ($epoch) = @_;
	return '-' if (!defined($epoch) || $epoch !~ /^\d+(?:\.\d+)?$/);
	return strftime('%Y-%m-%d %H:%M:%S %Z', localtime($epoch));
}

1;
