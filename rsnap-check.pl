#!/usr/bin/perl -w
#
# Author: Phillip Smith <fukawi2@gmail.com>
# Original Author: Till Elsner, till.elsner@henkel.com
#

use strict;
use warnings;

my $_USAGE = "Usage: $0 /path/to/rsnapshot.conf\n";

# EXIT STATES
my ( $OK, $WARNING, $CRITICAL, $UNKNOWN ) = ( 0, 1, 2, -1 );

# check if exactly one command line parameter was given
if ( $#ARGV ) {
	print STDERR "Wrong parameter count!\n";
	print $_USAGE;
	exit $UNKNOWN;
}

# print help
if ( $ARGV[0] eq "-h" ) {
	print $_USAGE;
	exit $OK;
}

# open config file
my ( @CONFIGFILE, $CONFIGFILE);
push @CONFIGFILE, $ARGV[0];

my ( $ROOT, %INTERVALS, %backup_destinations );
my $ESTATUS = $OK;

# read all config files
while ( $CONFIGFILE = shift @CONFIGFILE ) {
	# clear variables
	%INTERVALS = ();
	%backup_destinations = ();

	# open config file
	if (! open CONFIG, "< $CONFIGFILE" ) {
		print STDERR "Could not open config file $CONFIGFILE: $!\n";
		exit $UNKNOWN;
	}
	my @config_file = <CONFIG>;
	close CONFIG;
	chomp(@config_file);

	# read config
	ConfigLine:
	foreach my $line (@config_file) {
		next ConfigLine if ($line =~ m/^#|\s*^$/);

		my @confparam = split(/\t+/, $line);
		if		($confparam[0] eq "include_conf")	{ push @CONFIGFILE, $confparam[1] }
		elsif	($confparam[0] eq "snapshot_root")	{ $ROOT = &unslash_path($confparam[1]) }
		elsif	($confparam[0] eq "interval")		{ $INTERVALS{$confparam[1]} = $confparam[2] }
		elsif	($confparam[0] eq "backup") {
			#   0		  1								  2
			# backup	/mnt/natorgsvr/d/				natorgsvr.natorg.local/d/
			# backup	/mnt/warehousemgr-pc/c/VCSystem	warehousemgr-pc.natorg.local/VCSystem
			my $backup_src = &unslash_path($confparam[1]);
			my $backup_dst = &unslash_path($confparam[2]);
			if ( $backup_src =~ m/^([^@]+@[^:]+:)?\/?(.+)$/ ) {
				$backup_src = $2;
				&dbg(sprintf('Found backup source: %s ==> %s', $backup_src, $backup_dst));
				push(@{$backup_destinations{$backup_dst}}, $backup_src);
			}
		}
	}

	# check if snapshot root is defined
	unless ( $ROOT ) {
		print STDERR "No snapshot root defined!\n";
		exit $CRITICAL;
	}
	# check if intervals are defined
	unless ( %INTERVALS ) {
		print STDERR "No backup intervals defined!\n";
		exit $CRITICAL;
	}
	# check if backup point are defined
	unless ( %backup_destinations ) {
		print STDERR "No backup point defined!\n";
		exit $CRITICAL;
	}
	# check if backup root exists
	unless ( -d $ROOT ) {
		print STDERR "Backup root $ROOT does not exist!\n";
		exit $CRITICAL;
	}

	# Debug Output
	&dbg('Backup ROOT is: '.$ROOT);

	my %at_least_one;
	# Start from the top and work down....
	# FIRST: Each interval (eg, hourly, daily, weekly etc)
	Interval:
	foreach my $interval ( keys %INTERVALS ) {
		# SECOND: aged intervals (eg, xxx.0, xxx.1, xxx.2 etc)
		IntervalAge:
		foreach my $age ( 0 .. $INTERVALS{$interval}-1 ) {
			# Make sure this aged interval exists before digging deeper
			my $aged_interval = sprintf('%s.%s', $interval, $age);
			unless ( -d "$ROOT/$aged_interval" ) {
				print STDERR sprintf("WARNING: Missing aged interval: %s\n", $aged_interval);
				$ESTATUS = $WARNING;
				next IntervalAge;
			}

			# THIRD: does this interval age contain all the expected destinations?
			BackupDst:
			foreach my $expected_dst ( keys %backup_destinations ) {
				my $dst_path = sprintf('%s/%s', $aged_interval, $expected_dst);
				unless ( -d "$ROOT/$dst_path") {
					print STDERR sprintf("WARNING: Expected destination missing: %s\n", $dst_path);
					$ESTATUS = $WARNING;
					next BackupDst;
				}

				# FORTH: check if this backup destination contains all expect sources
				BackupSrc:
				foreach my $expected_src ( @{ $backup_destinations{$expected_dst} } ) {
					my $src_path = sprintf('%s/%s', $dst_path, $expected_src);
					unless ( -d "$ROOT/$src_path" ) {
						print STDERR sprintf("WARNING: Expected source missing: %s\n", $src_path);
						$ESTATUS = $WARNING;
						next BackupSrc;
					}
					# If we get here, then we have passed all the tests; Assume this is
					# a complete backup of the expected $ROOT/*/dst/src/
					$at_least_one{$expected_src} = 1;
				}
			}
		}
	}
	# check if at least one complete backup exists of every expected backup
	foreach my $expected_dst ( keys %backup_destinations ) {
		foreach my $expected_src ( @{ $backup_destinations{$expected_dst} } ) {
			unless ($at_least_one{$expected_src}) {
				print STDERR sprintf("[E] No complete backup found for: %s\n", $expected_src);
				$ESTATUS = $CRITICAL;
			}
		}
	}
}

# Everything is good :D
print "Backups OK\n" if ($ESTATUS == $OK);
exit $ESTATUS;

###############################################################################
## SUBROUTINES
###############################################################################

# print read config for debugging purposes
sub printconf {
	if ($CONFIGFILE) {
		print "Config file: $CONFIGFILE\n";
	} else {
		print "No config file given!\n";
		return;
	}
	$ROOT ? print "Snapshot root: $ROOT\n" : print "No snapshot root found\n";
	%INTERVALS ? print "Backup intervals: @{[ %INTERVALS ]}\n" : print "No backup intervals found";
	if ( %backup_destinations ) {
		print "Backup points:\n";
		foreach my $bpoint ( keys %backup_destinations) {
			print "$bpoint: @{ $backup_destinations{$bpoint} }\n";
		}
	} else {
		print "No backup info found\n";
	}
}

sub unslash_path {
	# Remove trailing slash from a path
	my ($path) = @_;
	$path =~ s/\/+\z//;
	return $path;
}

sub dbg {
	# Debug Helper
	return $OK;
	my ($msg) = @_; $msg = 'Unspecified Error' unless $msg;
	print "DEBUG: $msg\n";
}
