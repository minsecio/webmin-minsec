#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);

BEGIN { $ENV{'MINSEC_TESTING'} = 1; }
require './minsec-lib.pl'; ## no critic

%minsec::config = (
	'config_dir' => '/etc/minsec',
	'perpage' => 2,
);

is(minsec::format_duration(0), '0s', 'zero duration');
is(minsec::format_duration(90061), '1d 1h 1m 1s', 'compound duration');
is_deeply([minsec::validate_duration('5m')], [300, undef], 'duration parsed');
like((minsec::validate_duration('5x'))[1], qr/Invalid/, 'invalid duration rejected');

is_deeply([minsec::validate_network('192.0.2.4')], ['192.0.2.4/32', undef], 'IPv4 normalized');
is_deeply([minsec::validate_network('2001:db8::/48')], ['2001:db8::/48', undef], 'IPv6 network accepted');
like((minsec::validate_network('192.0.2.1/44'))[1], qr/prefix/, 'bad prefix rejected');

is_deeply([minsec::validate_filename('local-ssh.toml', 'filter')], ['local-ssh.toml', undef], 'safe filename');
like((minsec::validate_filename('../bad.toml', 'filter'))[1], qr/Unsafe/, 'traversal rejected');
like((minsec::validate_filename('bad.conf', 'dropin'))[1], qr/\.toml/, 'wrong suffix rejected');

is_deeply(minsec::map_service_state(2), {'running' => 1, 'boot' => 1, 'known' => 1, 'raw' => 2}, 'running service mapped');
is_deeply(minsec::map_service_state(1), {'running' => 0, 'boot' => 1, 'known' => 1, 'raw' => 1}, 'enabled stopped service mapped');
is_deeply(minsec::map_service_state(0), {'running' => 0, 'boot' => 0, 'known' => 1, 'raw' => 0}, 'disabled service mapped');

%minsec::access = ('view' => 1, 'raw' => 0);
ok(minsec::check_acl('view'), 'granted ACL accepted');
ok(!minsec::check_acl('raw'), 'denied ACL rejected');

my ($slice, $page) = minsec::paginate([1, 2, 3, 4, 5], 2, 2);
is_deeply($slice, [3, 4], 'pagination slice');
is_deeply($page, {'page' => 2, 'pages' => 3, 'total' => 5}, 'pagination metadata');

my $toml = minsec::render_webmin_toml({
	'defaults' => {'max_retries' => 5, 'ban_duration_seconds' => 600},
	'allowlist' => ['192.0.2.0/24', '2001:db8::/32'],
	'escalation' => {'enabled' => 'true'},
	'filters' => {'sshd' => {'enabled' => 'false'}},
});
like($toml, qr/^\[defaults\]$/m, 'defaults table emitted');
is(scalar(() = $toml =~ /^\[defaults\]$/mg), 1, 'defaults table emitted once');
like($toml, qr/allow = \["192\.0\.2\.0\/24", "2001:db8::\/32"\]/, 'allowlist serialized');
like($toml, qr/^\[filters\."sshd"\]$/m, 'filter override serialized');

my $root = tempdir(CLEANUP => 1);
my $config_dir = "$root/config";
make_path("$config_dir/conf.d", "$config_dir/filters");
open(my $main, '>', "$config_dir/minsec.toml") or die $!;
print {$main} "[defaults]\nmax_retries = 5\n";
close($main);
my $inspection = {
	'paths' => {'config_dir' => $config_dir},
	'files' => {
		'main' => "$config_dir/minsec.toml",
		'dropins' => ["$config_dir/conf.d/local.toml"],
		'custom_filters' => ["$config_dir/filters/myapp.toml"],
	},
};
is(minsec::discovered_file_kind($inspection, "$config_dir/minsec.toml"),
	'main', 'main configuration kind detected');
is(minsec::discovered_file_kind($inspection, "$config_dir/conf.d/local.toml"),
	'dropin', 'drop-in kind detected');
is(minsec::discovered_file_kind($inspection, "$config_dir/filters/myapp.toml"),
	'filter', 'custom filter kind detected');
is((minsec::allowed_file_path("$config_dir/conf.d/webmin.toml", $inspection, 1, 'dropin'))[0],
	"$config_dir/conf.d/webmin.toml", 'new drop-in path accepted');
like((minsec::allowed_file_path("$root/outside.toml", $inspection, 1, 'dropin'))[1], qr/outside/, 'outside path rejected');

my $target = "$config_dir/conf.d/webmin.toml";
my ($validation, $save_error) = minsec::staged_change(
	'config_dir' => $config_dir,
	'path' => $target,
	'content' => "[defaults]\nmax_retries = 8\n",
	'validator' => sub {
		my ($staged) = @_;
		return (-f "$staged/conf.d/webmin.toml" ? {'ok' => JSON::PP::true()} : undef, undef);
	},
);
ok($validation->{'ok'}, 'staged save validated');
ok(-f $target, 'validated file installed');

my (undef, $invalid_error) = minsec::staged_change(
	'config_dir' => $config_dir,
	'path' => $target,
	'content' => "invalid",
	'validator' => sub { return ({'ok' => JSON::PP::false()}, 'invalid TOML'); },
);
is($invalid_error, 'invalid TOML', 'failed validation reported');
open(my $saved, '<', $target) or die $!;
my $saved_content = do { local $/; <$saved> };
close($saved);
like($saved_content, qr/max_retries = 8/, 'invalid save rolled back');

my (undef, $delete_error) = minsec::staged_change(
	'config_dir' => $config_dir,
	'path' => $target,
	'delete' => 1,
	'validator' => sub { return ({'ok' => JSON::PP::true()}, undef); },
);
is($delete_error, undef, 'validated delete succeeds');
ok(!-e $target, 'validated delete applied');


{
	my $dir = tempdir(CLEANUP => 1);
	my $cmd = "$dir/minsec";
	{ package minsec; do './install_check.pl' or die $@; } ## no critic
	local %minsec::config = ('minsec_cmd' => $cmd, 'config_dir' => "$dir/etc");
	is(minsec::is_installed(1), 0, 'missing binary not installed');
	open(my $fh, '>', $cmd) or die $!;
	close($fh);
	chmod(0755, $cmd);
	is(minsec::is_installed(0), 1, 'binary present, mode 0');
	is(minsec::is_installed(1), 1, 'binary without config dir');
	make_path("$dir/etc");
	is(minsec::is_installed(1), 2, 'binary and config dir');
}

done_testing();
