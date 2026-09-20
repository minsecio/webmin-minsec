#!/usr/bin/perl
# Fake minsec state for screenshots. Nothing here touches the system.
#   setup DIR     write a config tree, events log and sample log under DIR
#   serve SOCKET  answer status/list/ban/unban on a Unix socket
use strict;
use warnings;
use File::Path qw(make_path);
use IO::Socket::UNIX;
use JSON::PP;

my $JSON = JSON::PP->new->canonical;
my $NOW = time();
my ($M, $H, $D) = (60, 3600, 86400);
my $UPTIME = 9 * $D + 4 * $H + 17 * $M;

my $seed = 20260919;
sub rnd { $seed = ($seed * 1103515245 + 12345) & 0x7fffffff; return $seed / 0x7fffffff }
sub pick { return $_[int(rnd() * @_)] }
sub between { my ($a, $b) = @_; return $a + int(rnd() * ($b - $a + 1)) }

# [net, filter, ttl, expires_in, hits, escalation]; undef filter is manual
my @BANS = map { { net => $_->[0], filter => $_->[1], ttl => $_->[2], expires_in => $_->[3], hits => $_->[4], escalation => $_->[5] } } (
	['203.0.113.42/32', 'sshd', $H, 2837, 3, 0],
	['198.51.100.17/32', 'sshd', $H, 3071, 3, 0],
	['203.0.113.200/32', 'sshd', 4 * $H, 4 * $H - 2388, 3, 2],
	['192.0.2.77/32', 'sshd', $H, 1544, 4, 0],
	['198.51.100.230/32', 'sshd', 32 * $H, 31 * $H + 900, 3, 5],
	['203.0.113.9/32', 'sshd', $H, 2210, 3, 0],
	['192.0.2.150/32', 'sshd', $H, 3402, 3, 0],
	['198.51.100.66/32', 'sshd', 8 * $H, 8 * $H - 140, 3, 3],
	['203.0.113.118/32', 'sshd', $H, 412, 3, 0],
	['2001:db8:4f2a:11::/64', 'sshd', 2 * $H, 2 * $H - 905, 3, 1],
	['192.0.2.33/32', 'dovecot', $H, 3299, 5, 0],
	['203.0.113.77/32', 'dovecot', $H, 1705, 5, 0],
	['198.51.100.8/32', 'dovecot', 2 * $H, 2 * $H - 700, 6, 1],
	['203.0.113.155/32', 'postfix-sasl', $H, 3556, 5, 0],
	['192.0.2.201/32', 'postfix-sasl', $H, 960, 5, 0],
	['2001:db8:91c:7::/64', 'postfix-sasl', $H, 2604, 5, 0],
	['198.51.100.99/32', 'webmin', $H, 3180, 5, 0],
	['203.0.113.61/32', 'webmin', 16 * $H, 16 * $H - 3955, 5, 4],
	['192.0.2.88/32', 'apache-auth', $H, 2930, 5, 0],
	['203.0.113.130/32', 'postfix', $H, 1180, 5, 0],
	['198.51.100.181/32', 'nextcloud', $H, 3490, 5, 0],
	['198.51.100.0/24', undef, 7 * $D, 6 * $D + 5 * $H, 0, 0],
	['192.0.2.250/32', undef, $D, 20 * $H + 300, 0, 0],
);

my %COUNTS = (
	'sshd' => [6218, 287], 'postfix-sasl' => [940, 61], 'dovecot' => [1203, 44],
	'postfix' => [312, 9], 'webmin' => [188, 12], 'apache-auth' => [57, 8], 'nextcloud' => [23, 3],
);
my %FILES = (
	'sshd' => ['/var/log/secure', '/var/log/auth.log'],
	'postfix-sasl' => ['/var/log/maillog', '/var/log/mail.log'],
	'dovecot' => ['/var/log/maillog', '/var/log/mail.log', '/var/log/dovecot.log'],
	'postfix' => ['/var/log/maillog', '/var/log/mail.log'],
	'webmin' => ['/var/webmin/miniserv.error', '/var/log/secure', '/var/log/auth.log'],
	'apache-auth' => ['/var/log/httpd/error_log', '/var/log/apache2/error.log'],
	'nextcloud' => ['/var/www/nextcloud/data/nextcloud.log'],
);
my %MAXRETRY = ('sshd' => 3);

sub status
{
	my @filters = map { {
		name => $_, files => $FILES{$_}, journal => $_ eq 'apache-auth' || $_ eq 'nextcloud' ? JSON::PP::false : JSON::PP::true,
		maxretry => $MAXRETRY{$_} || 5, findtime => 600, bantime => 3600,
		matched => $COUNTS{$_}[0], banned => $COUNTS{$_}[1],
	} } sort keys %COUNTS;
	my $banned = 2;
	$banned += $_->{banned} foreach (@filters);
	return { ok => JSON::PP::true, status => {
		version => '0.2.0', backend => 'nft', uptime => $UPTIME, tracked => 37, lines => 2148377,
		bans_total => $banned, active_bans => scalar(@BANS), filters => \@filters } };
}

sub list
{
	my @bans = map { { net => $_->{net}, expires_in => $_->{expires_in},
		filter => $_->{filter}, manual => $_->{filter} ? JSON::PP::false : JSON::PP::true } }
		sort { $a->{expires_in} <=> $b->{expires_in} } @BANS;
	return { ok => JSON::PP::true, bans => \@bans };
}

sub events
{
	my @events;
	push(@events, { kind => 'start', ts => $NOW - $UPTIME - 6 * $D, version => '0.1.4' });
	push(@events, { kind => 'stop', ts => $NOW - $UPTIME - 3 });
	push(@events, { kind => 'start', ts => $NOW - $UPTIME, version => '0.2.0' });
	foreach my $b (@BANS) {
		my $ts = $NOW - ($b->{ttl} - $b->{expires_in});
		push(@events, { kind => 'ban', ts => $ts, net => $b->{net}, filter => $b->{filter} || 'manual',
			ttl => $b->{ttl}, hits => $b->{hits}, escalation => $b->{escalation},
			manual => $b->{filter} ? JSON::PP::false : JSON::PP::true });
	}
	my @pools = ('203.0.113.', '198.51.100.', '192.0.2.');
	my @weighted = (('sshd') x 6, ('postfix-sasl') x 2, ('dovecot') x 2, 'webmin', 'apache-auth', 'postfix', 'nextcloud');
	for (1 .. 48) {
		my $filter = pick(@weighted);
		my $net = rnd() < 0.08
			? sprintf('2001:db8:%x:%x::/64', between(0x100, 0xffff), between(1, 0xfff))
			: pick(@pools).between(1, 254).'/32';
		my $escalation = rnd() < 0.2 ? between(1, 3) : 0;
		my $ttl = $H * 2 ** $escalation;
		my $ts = $NOW - between(2 * $H, $UPTIME - $H);
		my $need = $MAXRETRY{$filter} || 5;
		push(@events, { kind => 'ban', ts => $ts, net => $net, filter => $filter, ttl => $ttl,
			hits => $need + (rnd() < 0.3 ? between(1, 4) : 0), escalation => $escalation, manual => JSON::PP::false });
		push(@events, { kind => 'unban', ts => $ts + $ttl, net => $net, manual => JSON::PP::false }) if ($ts + $ttl < $NOW);
	}
	push(@events, { kind => 'ban', ts => $NOW - 2 * $D - 3 * $H, net => '203.0.113.250/32', filter => 'manual',
		ttl => 7 * $D, hits => 0, escalation => 0, manual => JSON::PP::true });
	push(@events, { kind => 'unban', ts => $NOW - $D - 5 * $H, net => '203.0.113.250/32', manual => JSON::PP::true });
	my @sorted = sort { $a->{ts} <=> $b->{ts} } @events;
	return @sorted;
}

my %TOML = (
	'minsec.toml' => <<'TOML',
# minsec main configuration. Drop-ins in conf.d/ override these values.

[defaults]
bantime  = "1h"       # initial ban length
findtime = "10m"      # window in which maxretry failures trigger a ban
maxretry = 5
backend  = "nft"      # nft | null (log only) | exec
escalate = { factor = 2, max = "1w", memory = "30d" }
allow = []
ipv6_prefix = 64
journal = true

[filters.sshd]
enabled = true
TOML
	'conf.d/sshd.toml' => "[filters.sshd]\nenabled = true\nmaxretry = 3\n",
	'conf.d/webmin.toml' => <<'TOML',
# Written by the Webmin module. Settings here override minsec.toml.

[defaults]
bantime = "1h"
findtime = "10m"
maxretry = 5
escalate_enabled = true
allow = ["10.20.0.0/16", "2001:db8:1::/48"]
backend = "nft"

[filters.webmin]
enabled = true
TOML
	'filters/nextcloud.toml' => <<'TOML',
# Nextcloud login failures. Requires log_type = "file" in config.php.

name = "nextcloud"
description = "Nextcloud login failures (from nextcloud.log)"
files = ["/var/www/nextcloud/data/nextcloud.log"]
ports = [80, 443]

prefilter = ["Login failed"]

patterns = [
  '''"message":"Login failed: <F-USER>[^"]+</F-USER> \(Remote IP: <HOST>\)''',
]

ignore = []
TOML
);
$TOML{"conf.d/$_.toml"} = "[filters.$_]\nenabled = true\n" foreach (qw(apache-auth dovecot postfix-sasl postfix));

sub setup
{
	my ($dir) = @_;
	make_path("$dir/etc/conf.d", "$dir/etc/filters", "$dir/state");
	$TOML{'minsec.toml'} .= "\n[paths]\nsocket = \"$dir/minsec.sock\"\nstate_dir = \"$dir/state\"\n";
	foreach my $name (sort keys %TOML) {
		open(my $fh, '>', "$dir/etc/$name") or die "$dir/etc/$name: $!";
		print {$fh} $TOML{$name};
		close($fh);
	}
	open(my $ev, '>', "$dir/state/events.jsonl") or die $!;
	print {$ev} $JSON->encode($_), "\n" foreach (events());
	close($ev);
	open(my $log, '>', "$dir/sshd-sample.log") or die $!;
	print {$log} <<'LOG';
Sep 18 23:41:07 web1 sshd[21877]: Invalid user admin from 203.0.113.42 port 51234
Sep 18 23:41:09 web1 sshd[21877]: Failed password for invalid user admin from 203.0.113.42 port 51234 ssh2
Sep 18 23:41:15 web1 sshd[21880]: Failed password for root from 198.51.100.17 port 40022 ssh2
Sep 18 23:41:18 web1 sshd[21880]: Failed password for root from 198.51.100.17 port 40022 ssh2
Sep 18 23:41:31 web1 sshd[21884]: Accepted publickey for alice from 10.20.4.8 port 55010 ssh2
Sep 18 23:41:40 web1 sshd[21890]: pam_unix(sshd:auth): authentication failure; logname= uid=0 euid=0 tty=ssh ruser= rhost=192.0.2.77 user=postgres
LOG
	close($log);
}

sub serve
{
	my ($path) = @_;
	unlink($path);
	my $server = IO::Socket::UNIX->new(Type => SOCK_STREAM, Local => $path, Listen => 5) or die "$path: $!";
	$| = 1;
	print "listening\n";
	while (my $client = $server->accept()) {
		my $line = <$client>;
		my $request = eval { $JSON->decode($line) } || {};
		my $cmd = $request->{cmd} || '';
		my $reply = $cmd eq 'status' ? status()
			: $cmd eq 'list' ? list()
			: $cmd eq 'ban' || $cmd eq 'unban' ? { ok => JSON::PP::true }
			: { ok => JSON::PP::false, error => "unknown command '$cmd'" };
		print {$client} $JSON->encode($reply), "\n";
		close($client);
	}
}

my ($mode, $arg) = @ARGV;
if (($mode || '') eq 'setup' && $arg) { setup($arg) }
elsif (($mode || '') eq 'serve' && $arg) { serve($arg) }
else { die "usage: $0 setup DIR | serve SOCKET\n" }
