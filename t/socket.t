#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use IO::Socket::UNIX;
use JSON::PP;
use Socket qw(SOCK_STREAM);
use Time::HiRes qw(sleep);

BEGIN { $ENV{'MINSEC_TESTING'} = 1; }
require './minsec-lib.pl'; ## no critic

my $root = tempdir(CLEANUP => 1);
my $socket_path = "$root/control.sock";

sub with_server
{
	my ($reply, $test) = @_;
	my $server = IO::Socket::UNIX->new('Type' => SOCK_STREAM, 'Local' => $socket_path, 'Listen' => 1) or die $!;
	my $pid = fork();
	die 'fork failed' if (!defined($pid));
	if (!$pid) {
		my $client = $server->accept();
		my $request = <$client>;
		if (ref($reply) eq 'CODE') {
			$reply->($client, $request);
		}
		else {
			print {$client} $reply;
		}
		close($client);
		close($server);
		exit 0;
	}
	close($server);
	$test->();
	waitpid($pid, 0);
	unlink($socket_path);
}

with_server(encode_json({'ok' => JSON::PP::true, 'bans' => []})."\n", sub {
	my ($response, $error) = minsec::socket_command($socket_path, {'cmd' => 'list'}, {'read_timeout' => 2});
	is($error, undef, 'socket request succeeds');
	is_deeply($response->{'bans'}, [], 'socket response parsed');
});

with_server(encode_json({'ok' => JSON::PP::false, 'error' => 'not allowed'})."\n", sub {
	my (undef, $error) = minsec::socket_command($socket_path, {'cmd' => 'ban'}, {'read_timeout' => 2});
	is($error, 'not allowed', 'daemon error reported');
});

with_server("not-json\n", sub {
	my (undef, $error) = minsec::socket_command($socket_path, {'cmd' => 'status'}, {'read_timeout' => 2});
	like($error, qr/Invalid JSON/, 'malformed response rejected');
});

with_server(sub {
	my ($client) = @_;
	sleep(1.2);
	print {$client} encode_json({'ok' => JSON::PP::true})."\n";
}, sub {
	my (undef, $error) = minsec::socket_command($socket_path, {'cmd' => 'status'}, {'read_timeout' => 1});
	like($error, qr/timed out/, 'socket timeout bounded');
});

done_testing();
