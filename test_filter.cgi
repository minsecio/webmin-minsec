#!/usr/bin/perl
use strict;
use warnings;
use File::Temp qw(tempfile);

require './minsec-lib.pl'; ## no critic
our (%in);
ReadParseMime();
minsec::require_post();
minsec::require_acl('filters');
my $name = $in{'name'} || '';
my $log_file = $in{'log_file'} || '';
my $temporary;
if (defined($in{'upload'}) && $in{'upload'} ne '') {
	error('Uploaded log is too large') if (length($in{'upload'}) > 10 * 1024 * 1024);
	my $handle;
	($handle, $temporary) = tempfile('minsec-filter-test-XXXXXX', 'TMPDIR' => 1, 'UNLINK' => 0);
	binmode($handle);
	print {$handle} $in{'upload'} or error('Cannot write uploaded log');
	close($handle) or error('Cannot close uploaded log');
	$log_file = $temporary;
}
my ($result, $test_error) = minsec::test_filter($name, $log_file);
unlink($temporary) if ($temporary);
error(minsec::html_escape($test_error)) if ($test_error);
ui_print_header('', 'Filter Test: '.minsec::html_escape($name), '', 'intro', 1, 1);
print minsec::navigation('filters');
print '<pre>'.minsec::html_escape(JSON::PP->new->canonical->pretty->encode($result)).'</pre>';
ui_print_footer('filter_edit.cgi?name='.urlize($name), 'filter policy');
