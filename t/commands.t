#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

BEGIN { $ENV{'MINSEC_TESTING'} = 1; }
require './minsec-lib.pl'; ## no critic

my $root = tempdir(CLEANUP => 1);
my $fake = "$root/minsec";
open(my $script, '>', $fake) or die $!;
print {$script} <<'FAKE';
#!/usr/bin/perl
use strict;
use warnings;
use JSON::PP;
my @args = @ARGV;
if (grep { $_ eq 'inspect' } @args) {
    print encode_json({schema_version => 1, version => '1.2.3', paths => {config_dir => '/tmp/minsec'}});
    exit 0;
}
if (grep { $_ eq 'check' } @args) {
    print encode_json({ok => JSON::PP::true, checked_filters => ['a', 'disabled-custom']});
    exit 0;
}
if (grep { $_ eq 'events' } @args) {
    print encode_json({event => 'ban', address => '192.0.2.1', timestamp => 1})."\n";
    print encode_json({event => 'unban', address => '192.0.2.1', timestamp => 2})."\n";
    exit 0;
}
if (grep { $_ eq 'test' } @args) {
    print encode_json({ok => JSON::PP::true, matched => 2, lines => 4});
    exit 0;
}
print encode_json({ok => JSON::PP::false, error => 'bad command'});
exit 2;
FAKE
close($script);
chmod(0755, $fake);

%minsec::config = ('minsec_cmd' => $fake, 'config_dir' => '/tmp/config', 'perpage' => 50);
my ($inspection, $inspect_error) = minsec::inspect('/tmp/config');
is($inspect_error, undef, 'inspect succeeds');
is($inspection->{'schema_version'}, 1, 'inspection schema version checked');
is($inspection->{'version'}, '1.2.3', 'inspection payload returned');

my ($check, $check_error) = minsec::check_config('/tmp/config');
is($check_error, undef, 'check succeeds');
is_deeply($check->{'checked_filters'}, ['a', 'disabled-custom'], 'check all result returned');

my ($events, $events_error) = minsec::read_events(10);
is($events_error, undef, 'JSONL events succeed');
is(scalar(@$events), 2, 'all JSONL events parsed');
is($events->[1]->{'event'}, 'unban', 'event fields retained');

my ($bad, $bad_error) = minsec::run_json_command([$fake, 'bad'], 3);
ok(!$bad->{'ok'}, 'structured command error retained');
is($bad_error, 'bad command', 'structured command error reported');

my $log = "$root/auth.log";
open(my $log_handle, '>', $log) or die $!;
print {$log_handle} "failed\nfailed\n";
close($log_handle);
my ($tested, $test_error) = minsec::test_filter('sshd', $log);
is($test_error, undef, 'filter test succeeds');
is($tested->{'matched'}, 2, 'filter test result returned');

my $bad_schema = "$root/bad-schema";
open(my $bad_handle, '>', $bad_schema) or die $!;
print {$bad_handle} "#!/bin/sh\nprintf '%s' '{\"schema_version\":2}'\n";
close($bad_handle);
chmod(0755, $bad_schema);
$minsec::config{'minsec_cmd'} = $bad_schema;
my (undef, $schema_error) = minsec::inspect('/tmp/config');
like($schema_error, qr/Unsupported inspection schema/, 'unknown schema rejected');

my $nft = "$root/nft";
open(my $nft_handle, '>', $nft) or die $!;
print {$nft_handle} <<'NFT';
#!/usr/bin/perl
use JSON::PP;
print encode_json({nftables => [
    {chain => {family => 'inet', table => 'minsec', name => 'input'}},
    {set => {family => 'inet', table => 'minsec', name => 'ban4', elem => ['192.0.2.1']}},
    {set => {family => 'inet', table => 'minsec', name => 'unrelated'}},
    {set => {family => 'ip', table => 'other', name => 'ban4'}},
    {counter => {family => 'inet', table => 'minsec', name => 'blocked', packets => 4}},
]});
NFT
close($nft_handle);
chmod(0755, $nft);
$minsec::config{'nft_cmd'} = $nft;
my ($nft_state, $nft_error) = minsec::nftables_state();
is($nft_error, undef, 'nftables JSON succeeds');
is(scalar(@{$nft_state->{'chains'}}), 1, 'minsec chain retained');
is(scalar(@{$nft_state->{'sets'}}), 1, 'only approved minsec set retained');
is($nft_state->{'sets'}->[0]->{'name'}, 'ban4', 'approved set name retained');
is(scalar(@{$nft_state->{'counters'}}), 1, 'minsec counter retained');

done_testing();
