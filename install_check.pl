#!/usr/bin/perl
use strict;
use warnings;

if ($^O ne 'linux') {
	print "Minsec is supported only on Linux systems\n";
	exit 1;
}

exit 0;

