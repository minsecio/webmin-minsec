#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%text);
minsec::require_acl('nftables');
my ($state, $error) = minsec::nftables_state();
ui_print_header('', $text{'nft_title'}, '', 'intro', 1, 1);
print minsec::navigation('nftables');
print ui_alert_box(minsec::html_escape($error), 'warning') if ($error);
if ($state) {
	foreach my $kind (qw(chains sets counters)) {
		my @rows;
		foreach my $object (@{$state->{$kind}}) {
			push(@rows, [
				minsec::html_escape($object->{'name'} || '-'),
				'<pre>'.minsec::html_escape(JSON::PP->new->canonical->pretty->encode($object)).'</pre>',
			]);
		}
		print ui_columns_table([ucfirst($kind), 'Details'], undef, \@rows);
	}
}
if (eval { main::foreign_check('nftables') }) {
	print ui_links_row([minsec::link_html('../nftables/', 'Open Nftables module')]);
}
ui_print_footer('index.cgi', $text{'index_dashboard'});
