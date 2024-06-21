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

# Name the volume group
my $VGName="Sample_VGroup";

# Name the logical volume 
my $LVName="Sample_LVolume";

my $vgret = 0;

#Check if the volume group is created locally
if( system("vgdisplay '$VGName' > /dev/null 2>&1") ){
	print "Volume group $VGName does not exist, creating now.\n";
	
	# Create the volume group
	$vgret = system("vgcreate -f $VGName ${opt_l} 2>/dev/null");
}else{
	print "Volume group $VGName already exists, skipping create of the volume group.\n";
}

if ($vgret != 0) {
	print "Failed to create Volume Group $VGName for ${opt_l} on the template server.\n";
	exit 1;
}

my $lvret = 0;
# Check if the logical volume is created locally 
if( system("lvdisplay '$VGName'/'$LVName' > /dev/null 2>&1") ){
	print "Logical volume $LVName does not exist, creating now.\n";
	
	# Create the logical volume
	$lvret = system("lvcreate -y --name $LVName -l 100%FREE $VGName 2>/dev/null");
}else{
	print "Logical volume $LVName exists, skipping create of the logical volume.\n";
}

if ($lvret != 0){
	print "Failed to create the Logical Volume for $LVName with $VGName on ${opt_l} on the template server.\n";
	exit 1;
}

@output = `modprobe $fsType >/dev/null 2>&1`;

# Build the name for the device to mirror
my $device = "/dev/mapper/$VGName-$LVName";

if ( ! -e $device ){
        print "The device $device does not exist on local system, cannot proceed with mirror creation.\n";
        exit 1;
}

#if we have resource instances for the mirror, skip trying to create the mirror
my $inslist_ret = system("$LKBIN/ins_list -R $mountPoint > /dev/null 2>&1");
if($inslist_ret){
        print "Resource instance for filesystem resource with tag \"$mountPoint\" does not exist, creating resource\n";
        $ret = system "$LKBIN/lkcli resource create dk --tag $LKDRTAG --mode $syncType --device $device --fstype $fsType --mount_point $mountPoint --fstag $mountPoint --hierarchy new";
}else{
        print "Resource instance for filesystem resource with tag \"$mountPoint\" already exists\n";
        $ret = 0;
}

# Determine if mirror creation succeeded
if ($ret != 0) {
        print "Failed to create the DataKeeper resource hierarchy\n";
        exit 1;
}

# Update LCD Database
system "$LKBIN/lcdsync";


# Check that the specified devices exists on the target server
@output = `$LKDIR/bin/lcdremexec -d $targetSys -- "if [ ! -b $opt_r ]; then echo no; else echo yes; fi"`;
if (($? != 0) || (grep(/^no/, @output))) {
	print "Specified device $opt_r does not exist on $targetSys\n";
	exit 1;
}

# command prefix for running commands remotely
my $remexec = "$LKBIN/lcdremexec -d $targetSys --";

# Check if the volume group is created on remote system

$vgret = 0;
if ( system("$remexec \"vgdisplay '$VGName' > /dev/null 2>&1 \"") ){
	print "Volume group $VGName does not exist on $targetSys, creating now.\n";
	
	# Create volume group remotely
	$vgret = system("$remexec \"vgcreate -f $VGName ${opt_r} 2>/dev/null\"");
}else{
	print "Volume group $VGName already exists on $targetSys, skipping create of the volume group.\n";
}

if ($vgret != 0) {
	print "Failed to create partition for $opt_r on the target  server.\n";
	exit 1;
}

# Check if the logical volume is created on remote system

$lvret = 0;
if( system("$remexec \"lvdisplay '$VGName'/'$LVName' > /dev/null 2>&1 \"") ){
	print "Logical volume $LVName does not exsist on $targetSys, creating now.\n";
	
	# Create logical volume remotely
	$lvret = system("$remexec \"lvcreate -y --name $LVName -l 100%FREE $VGName 2>/dev/null\"");
}else{
	print "Logical volume $LVName exists, skipping create of the logical volume.\n";
}

if ($lvret != 0){
	print "Failed to create the Logical Volume for $LVName with $VGName on ${opt_r} on the target system $targetSys.\n";
}

# Make sure the file system driver module is loaded on the target system
@output = `$remexec "modprobe $fsType"`;
foreach (@output) {
	chomp ($_);
	print "Modprobe output: $_\n";
}

my $laddr = (split('/', $mirrorPath))[0];
my $raddr = (split('/', $mirrorPath))[1];

my $eqvlist_ret = system("eqv_list -t $mountPoint > /dev/null 2>&1");
if( $eqvlist_ret ){
	print "Resource $mountPoint is not extended, extending now\n";
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
