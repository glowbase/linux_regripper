#! /usr/bin/perl -I ./ -I /opt/linux_regripper
#-------------------------------------------------------------------------
# Rip - RegRipper, CLI version
# Use this utility to run a plugins file or a single plugin against a Reg
# hive file.
# 
# Output goes to STDOUT
# Usage: see "_syntax()" function
#
# Change History
#   20230822 - minor tweak in plugin processing
#   20220714 - added JSON::PP based on input from Mark McKinnon
#   20210302 - added Digest::MD5
#   20200824 - Unicode parsing updates
#   20200803 - updated to version 4.0 Pro
#   20200427 - added getDateFromEpoch(), output date format in RFC 3339 profile of ISO 8601
#   20200331 - added "auto" capability...point rip at a hive, it determines the hive type and runs
#              hive-specific plugins automatically, obviating the need for profiles
#   20200324 - multiple updates
#   20190318 - modified code to allow the .exe to be run from anywhere within the file system
#   20190128 - added Time::Local, modifications to module Key.pm
#   20180406 - added "-uP" switch to update profiles
#   20130801 - added File::Spec support, for cross-platform compat.
#   20130716 - added 'push(@INC,$str);' line based on suggestion from
#              Hal Pomeranz to support Linux compatibility
#   20130425 - added alertMsg() functionality, updated to v2.8
#   20120506 - updated to v2.5 release
#   20110516 - added -s & -u options for TLN support
#   20090102 - updated code for relative path to plugins dir
#   20080419 - added '-g' switch (experimental)
#   20080412 - added '-c' switch
#
# copyright 2023 Quantum Analytics Research, LLC
# Author: H. Carvey, keydet89@yahoo.com
#-------------------------------------------------------------------------
use strict;
use Parse::Win32Registry qw(:REG_);
use Getopt::Long;
use Time::Local;
use File::Spec;
use Encode::Unicode;
use Digest::MD5;
use JSON::PP;
require 'time.pl';
require 'rr_helper.pl';

my %config;
Getopt::Long::Configure("prefix_pattern=(-|\/)");
GetOptions(\%config,qw(reg|r=s file|f=s csv|c dirty|d auto|a autoTLN|aT guess|g user|u=s sys|s=s plugin|p=s update|uP list|l help|?|h));

my @path = split(/\//,$0);
my $str = $0;
$str =~ s/($path[scalar(@path) - 1])//;

my $plugindir = File::Spec->catfile("plugins");

my $VERSION = "4\.0";

if ($config{help} || !%config) {
	_syntax();
	exit;
}

#-------------------------------------------------------------
# 
#-------------------------------------------------------------
if ($config{list}) {
	my @plugins;
	opendir(__DIR__,$plugindir) || die "Could not open $plugindir: $!\n";
	@plugins = readdir(__DIR__);
	closedir(__DIR__);

	my $count = 1; 
	print "Plugin,Version,Hive,MITRE ATT&CK,Category,Description\n" if ($config{csv});
	foreach my $p (@plugins) {
		next unless ($p =~ m/\.pl$/);
		my $pkg = (split(/\./,$p,2))[0];
		$p = File::Spec->catfile($plugindir,$p);
		eval {
			require $p;
			my %plugin   = $pkg->getConfig();
			my $hive     = $plugin{hive};
			$hive =~ s/\,/ /g;
			my $version  = $plugin{version};
			my $mitre    = $plugin{MITRE};
			my $category = $plugin{category};
			my $descr    = $pkg->getShortDescr();
			$descr =~ s/\,/;/g;
			
			if ($config{csv}) {
				print $pkg.",".$version.",".$hive.",".$mitre.",".$category.",".$descr."\n";
			}
			else {
				print $count.". ".$pkg." v.".$version." [".$hive."]\n";
				print  "   - ".$descr."\n\n";
				$count++;
			}
		};
		print "Error: $@\n" if ($@);
	}
	exit;
}

#-------------------------------------------------------------
# 
#-------------------------------------------------------------
if ($config{update}) {
	my @plugins;
	opendir(__DIR__, $plugindir) || die "Could not open $plugindir: $!\n";
	@plugins = readdir(__DIR__);
	closedir(__DIR__);
	my %files = ();

	foreach my $p (@plugins) {
		next unless ($p =~ m/\.pl$/);
		my $pkg = (split(/\./,$p,2))[0];
		$p = File::Spec->catfile($plugindir,$p);
		eval {
			require $p;
			my $hive    = $pkg->getHive();
			my @hives = split(/,/,$hive);
			foreach my $lch (@hives) {
				$lch =~ tr/A-Z/a-z/;
				$lch =~ s/\.dat$//;
				$lch =~ s/^\s+//;
				
				push(@{$files{$lch}},$pkg);
				
			}

		};
		print "Error: $@\n" if ($@);
	}

	foreach my $f (keys %files) {
		my $filepath = $plugindir."\\".$f;
		open(FH,">",$filepath) || die "Could not open ".$filepath." to write: $!";
		
		for my $i (0..$#{$files{$f}}) {
			next if ($files{$f}[$i] =~ m/tln$/);
			print FH $files{$f}[$i]."\n";
		}

		close(FH);	
	}
	exit;
}

#-------------------------------------------------------------
# 
#-------------------------------------------------------------
if ($config{file}) {
	my $hive = $config{reg};
	die "You must enter a hive file path/name.\n" if ($hive eq "");
	my %plugins = parsePluginsFile($config{file});
	if (%plugins) {
		logMsg("Parsed Plugins file.");
	}
	else {
		logMsg("Plugins file not parsed.");
		exit;
	}
	foreach my $i (sort {$a <=> $b} keys %plugins) {
		eval {
			my $plugin_file = File::Spec->catfile($plugindir,$plugins{$i}.".pl");
			require $plugin_file;
			$plugins{$i}->pluginmain($hive);
		};
		if ($@) {
			logMsg("Error in ".$plugins{$i}.": ".$@);
		}
		logMsg($plugins{$i}." complete.");
		rptMsg("-" x 40);
	}
	printAlerts();
}

#-------------------------------------------------------------
# 
#-------------------------------------------------------------
if ($config{reg} && $config{guess}) {
	my $hive = $config{reg};
	die "You must enter a hive file path/name.\n" if ($hive eq "");
	
	my $reg;
	my $root_key;
	my %guess = guessHive($hive);
	
	foreach my $g (keys %guess) {
		::rptMsg($g) if ($guess{$g} == 1);
	}
}

#-------------------------------------------------------------
# 
#-------------------------------------------------------------
if ($config{reg} && ($config{auto} || $config{autoTLN})) {
	my $hive = $config{reg};
	die "You must enter a hive file path/name.\n" if ($hive eq "");
	
	my $reg;
	my $root_key;
	my %guess = guessHive($hive);
	my $type = "";
	foreach my $g (keys %guess) {
		$type = $g if ($guess{$g} == 1);
	}
	
	my @plugins;

	opendir(DIR, $plugindir) || die "Could not open $plugindir: $!\n";
	@plugins = readdir(DIR);
	closedir(DIR);
	my %files = ();

	foreach my $p (@plugins) {
		next unless ($p =~ m/\.pl$/);
		my $pkg = (split(/\./,$p,2))[0];
		
		if ($config{auto}) {
			next if ($pkg =~ m/tln$/ || $pkg =~ m/json$/ || $pkg =~ m/yara$/ || $pkg =~ m/csv$/);
		}
		elsif ($config{autoTLN}) {
			next unless ($pkg =~ m/tln$/);
		}
		else {}

		$p = File::Spec->catfile($plugindir,$p);
		eval {
			require $p;
			my $hive    = $pkg->getHive();
			my @hives = split(/,/,$hive);
			foreach my $lch (@hives) {
				$lch =~ tr/A-Z/a-z/;
				$lch =~ s/\.dat$//;
				$lch =~ s/^\s+//;
				$type =~ tr/A-Z/a-z/;
				$files{$pkg} = 1 if ($lch eq $type);
			}
		};
		print "Error: $@\n" if ($@);
	}

	foreach my $f (sort keys %files) {
		eval {
			my $plugin_file = File::Spec->catfile($plugindir,$f.".pl");
			require $plugin_file;
			$f->pluginmain($hive);
		};
		if ($@) {
			logMsg("Error in ".$f.": ".$@);
		}
		rptMsg("-" x 40) unless ($config{autoTLN});
	}
}


#-------------------------------------------------------------
# 
#-------------------------------------------------------------
if ($config{plugin}) {
	my $hive = $config{reg};
	die "You must enter a hive file path/name.\n" if ($hive eq "");
	my $plugin = $config{plugin};
	my $pluginfile = File::Spec->catfile($plugindir,$config{plugin}."\.pl");
	die $pluginfile." not found.\n" unless (-e $pluginfile);
	
	eval {
		require $pluginfile;
		$plugin->pluginmain($hive);
	};
	if ($@) {
		logMsg("Error in ".$pluginfile.": ".$@);
	}	
}

#-------------------------------------------------------------
# 
#-------------------------------------------------------------
sub _syntax {
	print<< "EOT";
Rip v.$VERSION - CLI RegRipper Tool

Rip [-r Reg hive file] [-f profile] [-p plugin] [options]
Parse Windows Registry files, using either a single module, or a profile.

  -r [hive] .........Registry hive file to parse
  -d ................Check to see if the hive is dirty 
  -g ................Guess the hive file type 
  -a ................Automatically run hive-specific plugins 
  -aT ...............Automatically run hive-specific TLN plugins 
  -f [profile].......use the profile 
  -p [plugin]........use the plugin
  -l ................list all plugins
  -c ................Output plugin list in CSV format (use with -l)
  -s systemname......system name (TLN support)
  -u username........User name (TLN support)
  -uP ...............Update default profiles
  -h.................Help (print this information)

EOT
}

#-------------------------------------------------------------
# 
#-------------------------------------------------------------
sub logMsg {
	print STDERR $_[0]."\n";
}

#-------------------------------------------------------------
# 
#-------------------------------------------------------------
sub rptMsg {
	binmode STDOUT,":utf8";
	if ($config{sys} || $config{user}) {
		my @vals = split(/\|/,$_[0],5);
		my $str = $vals[0]."|".$vals[1]."|".$config{sys}."|".$config{user}."|".$vals[4];
		print $str."\n";
	}
	else {
		print $_[0]."\n";
	}
}

#-------------------------------------------------------------
# parsePluginsFile()
# Parse the plugins file and get a list of plugins
#-------------------------------------------------------------
sub parsePluginsFile {
	my $file = $_[0];
	my %plugins;
# Parse a file containing a list of plugins
# Future versions of this tool may allow for the analyst to 
# choose different plugins files	
#	my $pluginfile = $plugindir.$file;
	my $pluginfile = File::Spec->catfile($plugindir,$file);
	if (-e $pluginfile) {
		open(FH,"<",$pluginfile);
		my $count = 1;
		while(<FH>) {
			chomp;
			next if ($_ =~ m/^#/ || $_ =~ m/^\s+$/);
#			next unless ($_ =~ m/\.pl$/);
			next if ($_ eq "");
			$_ =~ s/^\s+//;
			$_ =~ s/\s+$//;
			$plugins{$count++} = $_; 
		}
		close(FH);
		return %plugins;
	}
	else {
		return undef;
	}
}

#-------------------------------------------------------------
# guessHive()
# 
#-------------------------------------------------------------
sub guessHive {
	my $hive = shift;
	my $reg;
	my $root_key;
	my %guess;
	eval {
		$reg = Parse::Win32Registry->new($hive);
	  $root_key = $reg->get_root_key;
	};
	$guess{unknown} = 1 if ($@);
#-------------------------------------------------------------
# updated 20200324
# see if we can get the name from the hive file	
	my $embed = $reg->get_embedded_filename();
	my @n = split(/\\/,$embed);
	my $r = $n[scalar(@n) - 1];
	$r =~ tr/A-Z/a-z/;
	my $name = (split(/\./,$r,2))[0];
	$guess{$name} = 1;
#-------------------------------------------------------------

# Check for SAM
	eval {
		$guess{sam} = 1 if (my $key = $root_key->get_subkey("SAM\\Domains\\Account\\Users"));
	};
# Check for Software	
	eval {
		$guess{software} = 1 if ($root_key->get_subkey("Microsoft\\Windows\\CurrentVersion") &&
				$root_key->get_subkey("Microsoft\\Windows NT\\CurrentVersion"));
	};

# Check for System	
	eval {
		$guess{system} = 1 if ($root_key->get_subkey("MountedDevices") &&
				$root_key->get_subkey("Select"));
	};
	
# Check for Security	
	eval {
		$guess{security} = 1 if ($root_key->get_subkey("Policy\\Accounts") &&
				$root_key->get_subkey("Policy\\PolAdtEv"));
	};
# Check for NTUSER.DAT	
	eval {
		$guess{ntuser} = 1 if ($root_key->get_subkey("Software\\Microsoft\\Windows\\CurrentVersion")&&
				$root_key->get_subkey("Software\\Microsoft\\Windows NT\\CurrentVersion"));
		
	};	
	
	eval {
		$guess{usrclass} = 1 if ($root_key->get_subkey("Local Settings\\Software") &&
				$root_key->get_subkey("lnkfile"));
	};
	
	return %guess;
}

#-------------------------------------------------------------
# checkHive()
# check to see if hive is "dirty"
# Added 20200220
#-------------------------------------------------------------
sub checkHive {
	my $hive = shift;
	my $reg = Parse::Win32Registry->new($hive);
	my $dirty;
	::rptMsg("***Hive Check***");
	if ($reg->is_dirty() == 1) {
		::rptMsg("The hive (".$hive.") is dirty.");
		::rptMsg("");
		::rptMsg("Please consider processing hive transaction logs via either Maxim's yarp + registryFlush.py");
		::rptMsg("or via Eric Zimmerman's rla.exe.");
	}
	elsif ($reg->is_dirty() == 0) {
		::rptMsg("Hive is not dirty.");
	}
	else {
		::rptMsg("Unknown if hive is dirty.");
	}
	::rptMsg("");
}
