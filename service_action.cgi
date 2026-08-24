#!/usr/bin/perl
use strict;
use warnings;

require './minsec-lib.pl'; ## no critic
our (%in, %text);
ReadParse();
minsec::require_post();
my $action = $in{'action'} || '';
minsec::require_acl($action =~ /\A(?:enable|disable)\z/ ? 'boot' : 'service');
my ($ok, $error) = minsec::service_action($action);
error(minsec::html_escape($error)) if (!$ok);
webmin_log($action, 'service', minsec::settings()->{'service_name'});
redirect('index.cgi');

