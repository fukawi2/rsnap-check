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

my ( $ROOT, %INTERVALS, %BACKUPFS );
my $ESTATUS = $OK;

# read all config files
while ( $CONFIGFILE = shift @CONFIGFILE ) {
	# clear variables
	%INTERVALS = ();
	%BACKUPFS = ();

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
		elsif	($confparam[0] eq "snapshot_root")	{ $ROOT = $confparam[1] }
		elsif	($confparam[0] eq "interval")		{ $INTERVALS{$confparam[1]} = $confparam[2] }
		elsif	($confparam[0] eq "backup") {
			push @{ $BACKUPFS{$confparam[2]} }, $2 if ( $confparam[1] =~ /^([^@]+@[^:]+:)?(.+)$/ );
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
	unless ( %BACKUPFS ) {
		print STDERR "No backup point defined!\n";
		exit $CRITICAL;
	}

	# check if backup root exists
	unless ( -d $ROOT ) {
		print STDERR "Backup root $ROOT does not exist!\n";
		exit $CRITICAL;
	}

	# check backup directories for each interval
	my %at_least_one;
	IntervalName:
	foreach my $interval ( keys %INTERVALS ) {
		IntervalNumber:
		foreach ( 0 .. $INTERVALS{$interval}-1 ) {
			# $intervaldir holds "$ROOT/hourly.0" etc
			my $intervaldir = sprintf('%s/%s.%s', $ROOT, $interval, $_);

			# Make sure the intervaldir exists; if not then warn and goto next numbered interval
			unless ( -d $intervaldir ) {
				print STDERR "WARNING: Backup directory '$intervaldir' not found!\n";
				$ESTATUS = $WARNING;
				next IntervalNumber
			}

			# check backup points inside $intervaldir
			BackupPoint:
			foreach my $bpoint ( keys %BACKUPFS ) {
				my $failure = 0;
				# This block checks for mid-level backup destinations
				#   eg. $ROOT/hourly.0/host.example.com/
				my $bpointdir = sprintf('%s/%s', $intervaldir, $bpoint);
				unless ( -d $bpointdir ) {
					print STDERR "WARNING: Backup point $bpointdir missing!\n";
					$ESTATUS = $WARNING;
					$failure = 1;
					next BackupPoint;
				}

				# for each backup point, check if it is complete
				BackupSrc:
				foreach ( @{ $BACKUPFS{$bpoint} } ) {
					# This block checks for lowest-level backup destinations
					#   eg. $ROOT/hourly.0/host.example.com/home/username/Maildir/
					my $src = $bpointdir.&strip_leading_slash($_);
					unless ( -d $src ) {
						# if not, set warning and exit check for this backup point
						print STDERR 'WARNING: Backup point '.$src." incomplete!\n";
						$ESTATUS = $WARNING;
						$failure = 1;
					}
				}

				$at_least_one{$interval}{$bpoint} = 1 unless ( $failure );
			}
		}
	}

	# check if at least one complete backup exists per interval and mount point
	foreach my $interval ( keys %INTERVALS ) {
		foreach my $bpoint ( keys %BACKUPFS ) {
			unless ( $at_least_one{$interval}{$bpoint} ) {
				print STDERR sprintf("No complete '%s' backup found for backup point '%s'!\n", $interval, $bpoint);
				$ESTATUS = $CRITICAL;
			}
		}
	}
}

( $ESTATUS != $OK ) ? exit $ESTATUS : print "Backups OK\n";
exit $OK;

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
	if ( %BACKUPFS ) {
		print "Backup points:\n";
		foreach my $bpoint ( keys %BACKUPFS) {
			print "$bpoint: @{ $BACKUPFS{$bpoint} }\n";
		}
	} else {
		print "No backup info found\n";
	}
}

sub strip_leading_slash {
	my ($s) = @_;
	$s =~ s/^\/(.*)$/$1/;
	return $s
}
