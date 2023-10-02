#!/opt/LifeKeeper/bin/perl
#
# Copyright (c) SIOS Technology, Corp.
#
#	Description: Create LifeKeeper Comm Path (on side)
#
#	Options: -l: local IP address
#	Options: -r: remote IP address
#	Options: -s: remote system name
#
# Exit Codes:
#	0 - Comm path added successfully
#	1 - Failed to add comm path
#

BEGIN { require '/etc/default/LifeKeeper.pl'; }
use LK;
use strict;
use Getopt::Std;
use vars qw($opt_l $opt_r $opt_s);

my $ret;

#
# Usage
#
sub usage {
	print "Usage:\n";
	print "\t-l <local IP address>\n";
	print "\t-r <remote IP address>\n";
	print "\t-s <remote system name>\n";
	exit 1;
}

#
# Add remote system to system list
#
# Return codes:
#	0 - failed to add system
#	1 - system added without error
#
sub AddRemoteSystem {
	my $remoteSys = shift;
	my $me = LK::lcduname();
	my @results;
	my $retCode;

	# Check and make sure the system has not already been added
	@results = `sys_list 2>&1`;
	$retCode = $? >> 8;
	if ($retCode != 0) {
		print "Failed to run sys_list.  Reason:\n";
		foreach (@results) {
			print "$_";
		}
	} else {
		foreach (@results) {
			if ($_ =~ m/$remoteSys/) {
				print "Destination system already added. Continuing ...\n";
				return 1;
			}
		}
	}

	# Add the system
	@results = `sys_create -d $me -s $remoteSys 2>&1`;
	$retCode = $? >> 8;
	if ($retCode != 0) {
		print "Failed to add remote system.  Error: $retCode Reason:\n";
		foreach (@results) {
			print "$_";
		}
		return 0;
	}

	return 1;
}

#
# Add network path to other node.
#
# Return codes:
#	0 - failed to add network
#	1 - network path added without error
#
sub AddNetPath {
	my $remoteSys = shift;
	my $localIP = shift;
	my $remoteIP = shift;
	my $me = LK::lcduname();
	my @results;
	my $retCode;

	# Add the network path
	@results = `net_create -d $me -n TCP -r $remoteIP -l $localIP -s $remoteSys 2>&1`;
	$retCode = $? >> 8;
	if ($retCode != 0) {
		print "Failed to add network path.  Error: $retCode Reason:\n";
		foreach (@results) {
			print "$_";
		}
		return 0;
	}

	return 1;
}

#
# Main body of script
#
getopts('l:r:s:');
if ($opt_l eq '' || $opt_r eq '' || $opt_s eq '') {
	usage();
}

if (AddRemoteSystem($opt_s)) {
	if (AddNetPath($opt_s, $opt_l, $opt_r)) {
		exit 0;
	}
}

exit 1;
