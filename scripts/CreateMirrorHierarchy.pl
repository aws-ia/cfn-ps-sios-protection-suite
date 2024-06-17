#!/opt/LifeKeeper/bin/perl
#
# Copyright (c) SIOS Technology, Corp.
#
#	Description: Create and extend a mirrored file system hierarchy
#
#	Options: -l: local device
#	Options: -r: remote system device
#
# Exit Codes:
#	0 - Hierarhcy created and extended successfully
#	1 - Failed create and/or extend successfully
#

BEGIN { require '/etc/default/LifeKeeper.pl'; }
use LK;
use strict;
use Getopt::Std;
use vars qw($opt_f $opt_l $opt_m $opt_r $opt_s);

my $LKDIR="$ENV{LKROOT}";
my $LKBIN="$LKDIR/bin";
my $LKDRBIN="$LKDIR/lkadm/subsys/scsi/netraid/bin";
my $LKDRTAG="datarep-sample";
my $SWITCHBACK="intelligent";
my $NETRAIDTYPE="Replicate New Filesystem";
my $MOUNTPOINT="/opt/sample_mirror";
my $FSTYPE="xfs";
my $SYNCTYPE="synchronous";
my $BITMAP="/opt/LifeKeeper/bitmap__opt_sample_mirror";
my $BUNDLEADDITION=""; # null for 1x1 mirror
my $TARGETPRIORITY=10;

my $ret;
my $templateSys;
my $targetSys;
my $mountPoint;
my $syncType;
my $fsType;
# Setup the replication path
chomp (my $mirrorPath=`$LKDIR/bin/net_list | cut -d  -f 2`);
my @systems=`$LKDIR/bin/sys_list`;
my @output;

#
# Usage
#
sub usage {
	print "Usage:\n";
	print "\t-l <local device for replication>\n";
	print "\t-r <remote device for replication>\n";
	exit 1;
}

#
# Verify extendability of resource instance
#
# Return codes:
#       0 - canextend succeeded
#       1 - canextend failed
#
sub CanextendCheck {
	my $tag = shift;
	my $appType = shift;
	my $resType = shift;
	my $retCode;
	my $canextendOutputFile="/tmp/CanextendTest.$$";
	my $canextendScript="$LKDIR/lkadm/subsys/$appType/$resType/bin/canextend";

	if ( ! -f $canextendScript ) {
		print STDERR "FAIL: No canextend script exists for $appType / $resType\n";
		return 1;
	}

	system ("$LKDIR/bin/lcdremexec -d $targetSys -- \"$canextendScript $templateSys $tag\"; echo \$? >$canextendOutputFile");
	chomp ($retCode=`head $canextendOutputFile`);
	unlink $canextendOutputFile;
	if ($retCode != 0 ) {
		print "FAIL: canextend for hier $tag failed.  The resource cannot be extended to $targetSys \n";
		return 1;
	}
}


#
# Main body of script
#
getopts('f:l:m:r:s:');
if ($opt_l eq '' || $opt_r eq '') {
	usage();
}

if ($opt_f eq '') {
	$fsType = $FSTYPE;
} else {
	if ($opt_f =~ /^ext3$/ || $opt_f =~ /^ext4$/ || $opt_f =~ /^xfs$/) {
		$fsType = $opt_f;
	} else {
		print "File system type $opt_f is not supported\n";
		exit 1;
	}
}

if ($opt_m eq '') {
	$mountPoint = $MOUNTPOINT;
} else {
	$mountPoint = $opt_m;
}

if ($opt_s eq '') {
	$syncType = $SYNCTYPE;
} else {
	if ($opt_s =~ /^synchronous$/ || $opt_s =~ /^asynchronous$/ ) {
		$syncType = $opt_s;
	} else {
		print "Sync type $opt_s is not supported\n";
		exit 1;
	}
}

# Set the Template and Target system values
$templateSys = LK::lcduname;
chomp (@systems);
foreach (@systems) {
	next if ($_ =~ /^$templateSys$/);
	$targetSys = $_;
}

# Check that the specified devices exists on the template server
if (! -b $opt_l) {
	print "Specified device $opt_l does not exist on $templateSys\n";
	exit 1;
}

# create a default partition on the specified device on the template system


my $localPartition = "${opt_l}1";
`parted ${opt_l} --script mklabel gpt mkpart xfspart xfs 0% 100%`;
if ($? != 0) {
	print "Failed to create partition for ${opt_l} on the template server.\n";
	exit 1;
}

# Check that the specified devices exists on the target server
@output = `$LKDIR/bin/lcdremexec -d $targetSys -- "if [ ! -b $opt_r ]; then echo no; else echo yes; fi"`;
if (($? != 0) || (grep(/^no/, @output))) {
	print "Specified device $opt_r does not exist on $targetSys\n";
	exit 1;
}

# create a default partition on the specified device on the target system

my $targetPartition = "${opt_r}1";
`$LKBIN/lcdremexec -d $targetSys -- "parted ${opt_r} --script mklabel gpt mkpart xfspart xfs 0% 100%"`;
if ($? != 0) {
	print "Failed to create partition for $opt_r on the template server.\n";
	exit 1;
}

# Make sure the file system driver module is loaded on the template
@output = `modprobe $fsType >/dev/null 2>&1`;


my $localPartition = "${opt_l}1";

#if we have resource instances for the mirror, skip trying to create the mirror
my $inslist_ret = system("$LKBIN/ins_list -R $mountPoint > /dev/null 2>&1");
if($inslist_ret){
	print "Resource instance for filesystem resource with tag \"$mountPoint\" does not exist, creating resource\n";
	$ret = system "$LKBIN/lkcli resource create dk --tag $LKDRTAG --mode $syncType --device $localPartition --fstype $fsType --mount_point $mountPoint --fstag $mountPoint --hierarchy new";	
}else{
	print "Resource instance for filesystem resource with tag \"$mountPoint\" already exists\n";
	$ret = 0;
}

# Determine if mirror creation succeeded
if ($ret != 0) {
	print "Failed to create the scsi netraid resource hierarchy\n";
	exit 1;
}

# Update LCD Database
system "$LKDIR/bin/lcdsync";

# Make sure the file system driver module is loaded on the target system
@output = `$LKDIR/bin/lcdremexec -d $targetSys -- "modprobe $fsType "`;
foreach (@output) {
	chomp ($_);
	print "Modprobe output: $_\n";
}

my $laddr = (split('/', $mirrorPath))[0];
my $raddr = (split('/', $mirrorPath))[1];

my $eqvlist_ret = system("eqv_list -t $mountPoint > /dev/null 2>&1");
if( $eqvlist_ret ){
	print "Resource $mountPoint is not extended, extending now\n";
	print "$LKBIN/lkcli resource extend dk --tag $LKDRTAG --dest $targetSys --mode $syncType --laddr $laddr -raddr $raddr --fstag $mountPoint --switchback $SWITCHBACK --target_priority $TARGETPRIORITY";
	$ret = system "$LKBIN/lkcli resource extend dk --tag $LKDRTAG --dest $targetSys --mode $syncType --laddr $laddr -raddr $raddr --fstag $mountPoint --switchback $SWITCHBACK --target_priority $TARGETPRIORITY";
}else{
	print "Resource $mountPoint is already extended, skipping extend on already extended resource\n";
	$ret = 0;
}

if ($ret != 0) {
	print "Failed to extend the resource hierarchy\n";
	exit 1;
}

exit 0;
