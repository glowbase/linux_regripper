#-----------------------------------------------------------
# appcompatcache_json.pl
#
# History:
#  20221129 - modified for JSON output
#  20220920 - updated Win8.1 parsing 
#  20200730 - minor updates
#  20200428 - updated output date format
#  20190112 - updated parsing for Win8.1
#  20180311 - updated for more recent version of Win10/Win2016
#  20160528 - updated code to not de-dup entries based on filename
#  20160217 - updated to correctly support Win10
#  20150611 - mod'd for Kevin Pagano
#  20150429 - updated to support Win10
#  20140724 - update based on data provided by Shafik Punja
#  20130801 - added initial Win8 support; very alpha at the moment
#  20130603 - updated alerts
#  20130509 - added additional alerts/warnings 
#  20130425 - added alertMsg() functionality
#  20120817 - updated to address issue with residual data in XP data blocks
#  20120722 - updated the %config hash
#  20120523 - updated to send all files to a single hash, and check for temp paths
#  20120515 - Updated to support 64-bit Win2003 and Vista/Win2008
#  20120424 - Modified/updated 
#  20120418 - created
#
# References:
#  https://binaryforay.blogspot.com/2016/05/appcompatcacheparser-v0900-released-and.html
#  Blog post: https://blog.mandiant.com/archives/2459
#  Whitepaper: http://fred.mandiant.com/Whitepaper_ShimCacheParser.pdf
#  Tool: https://github.com/mandiant/ShimCacheParser
#  Win10: http://binaryforay.blogspot.com/2015/04/appcompatcache-changes-in-windows-10.html
#  JSON: https://developer.mozilla.org/en-US/docs/Learn/JavaScript/Objects/JSON
#
# This plugin is based solely on the work and examples provided by Mandiant;
# thanks to them for sharing this information, and making the plugin possible.
# 
# copyright 2022 Quantum Analytics Research, LLC
# Author: H. Carvey, keydet89@yahoo.com
#-----------------------------------------------------------
package appcompatcache_json;
use strict;

my %config = (hive          => "System",
			  category      => "file existence",
              hasShortDescr => 1,
              hasDescr      => 0,
              hasRefs       => 0,
              MITRE         => "",
			  output        => "json",
              version       => 20220920);

sub getConfig{return %config}
sub getShortDescr {
	return "Parse files from System hive AppCompatCache";	
}
sub getDescr{}
sub getRefs {}
sub getHive {return $config{hive};}
sub getVersion {return $config{version};}

my $VERSION = getVersion();
my %files;
my $str = "";

sub pluginmain {
	my $class = shift;
	my $hive = shift;
#	::logMsg("Launching appcompatcache v.".$VERSION);
#	::rptMsg("appcompatcache v.".$VERSION); # banner
#    ::rptMsg("(".$config{hive}.") ".getShortDescr()."\n"); # banner 
	my $reg = Parse::Win32Registry->new($hive);
	my $root_key = $reg->get_root_key;
# First thing to do is get the ControlSet00x marked current...this is
# going to be used over and over again in plugins that access the system
# file
	my $ccs = ::getCCS($root_key);
	my $key;
	my $appcompat;
	my $appcompat_path = $ccs."\\Control\\Session Manager";
	if ($appcompat = $root_key->get_subkey($appcompat_path)) {
			
		my $app_data;
			
		eval {
			$app_data = $appcompat->get_subkey("AppCompatibility")->get_value("AppCompatCache")->get_data();
			::rptMsg("{");
			::rptMsg("\t\"key\": \".$appcompat_path.\"");
			::rptMsg("\t\"value\": \"AppCompatibility\"");
			::rptMsg("\t\"LastWrite Time\": \"".::format8601Date($appcompat->get_subkey("AppCompatibility")->get_timestamp())."Z\"");
		};
			
		eval {
			$app_data = $appcompat->get_subkey("AppCompatCache")->get_value("AppCompatCache")->get_data();
			::rptMsg("{");
			::rptMsg("  \"pluginname\": \"appcompatcache_json\"");
			::rptMsg("  \"description\": \"query\\parse the appcompatcache\\shimcache data source\"");
			::rptMsg("  \"key\": \".$appcompat_path.\"");
			::rptMsg("  \"value\": \"AppCompatCache\"");
			::rptMsg("  \"LastWrite Time\": \"".::format8601Date($appcompat->get_subkey("AppCompatCache")->get_timestamp())."Z\"");
		};
				
#		::rptMsg("Length of data: ".length($app_data));
#		::probe($app_data);
		my $sig = unpack("V",substr($app_data,0,4));
#		::rptMsg(sprintf "Signature: 0x%x",$sig);
			
		if ($sig == 0xdeadbeef) {
			eval {
				appXP32Bit($app_data);
			};
		}
		elsif ($sig == 0xbadc0ffe) {
			eval {
				appWin2k3($app_data);
			};
		}
		elsif ($sig == 0xbadc0fee) {
			eval {
				appWin7($app_data);
			};
			
		}
		elsif ($sig == 0x80) {
#				::rptMsg("Possible Win8 system\.");
#				::rptMsg(sprintf "Data Length: 0x%08x",length($app_data));
			appWin8($app_data);
#				probe($app_data);
				
		}
		elsif ($sig == 0x0) {
# possible win 8.1 system
			appWin81($app_data);			
#				print $app_data;	
		}
		elsif ($sig == 0x30 || $sig == 0x34) {
# Windows 10 system
			appWin10($app_data);				
		}
		else {
			::rptMsg(sprintf "Unknown signature: 0x%x",$sig);
#				probe($app_data);
		}
# this is where we print out the files
		::rptMsg("  \"members\": [");
		foreach my $f (keys %files) {
#				::rptMsg($f);

			my $modtime = $files{$f}{modtime};
			if ($modtime == 0) {
				$modtime = "";
			}
			else {
				$modtime = ::format8601Date($modtime);
			}
			::rptMsg("    {");
			::rptMsg("      \"value\": \"".$files{$f}{filename}."\"");
			::rptMsg("      \"data\": \"".$modtime."\"");
			::rptMsg("    },");
#			$str = $files{$f}{filename}."  ".$modtime;
#			$str .= "  ".::format8601Date($files{$f}{updtime}) if (exists $files{$f}{updtime});
#			$str .= "  ".$files{$f}{size}." bytes" if (exists $files{$f}{size});
#			$str .= "  Executed" if (exists $files{$f}{executed});
#			::rptMsg($str);
		}
		::rptMsg("  ]");
		::rptMsg("}");
	}
	else {
		::rptMsg($appcompat_path." not found.");
	}
}

#-----------------------------------------------------------
# appXP32Bit()
# parse 32-bit XP data
#-----------------------------------------------------------
sub appXP32Bit {
	my $data = shift;
	::rptMsg("WinXP, 32-bit");
# header is 400 bytes; each structure is 552 bytes in size
	my $num_entries = unpack("V",substr($data,4,4));
	
	foreach my $i (0..($num_entries - 1)) {
		my $x = substr($data,(400 + ($i * 552)),552);
		my $file = (split(/\00\00/,substr($x,0,488)))[0];
		$file =~ s/\00//g;
		$file =~ s/^\\\?\?\\//;
		my ($mod1,$mod2) = unpack("VV",substr($x,528,8));
		my $modtime      = ::getTime($mod1,$mod2);
		my ($sz1,$sz2)   = unpack("VV",substr($x,536,8));
		my $sz;
		($sz2 == 0)?($sz = $sz1):($sz = "Too big");
		my ($up1,$up2)   = unpack("VV",substr($x,544,8));
		my $updtime      = ::getTime($up1,$up2);
		
		$files{$i}{filename} = $file;
		$files{$i}{size} = $sz;
		$files{$i}{modtime} = $modtime;
		$files{$i}{updtime} = $updtime;
	}
}
#-----------------------------------------------------------
# appWin2k3()
# parse Win2k3, Vista, Win2k8 data
#-----------------------------------------------------------
sub appWin2k3 {
	my $data = shift;
	my $num_entries = unpack("V",substr($data,4,4));
#	::rptMsg("Num_entries: ".$num_entries);
	my $struct_sz = 0;
	my ($len,$max_len,$padding) = unpack("vvV",substr($data,8,8));
	if (($max_len - $len) == 2) {
# if $padding == 0, 64-bit; otherwise, 32-bit
		if ($padding == 0) {
			$struct_sz = 32;
			::rptMsg("Win2K3/Vista/Win2K8, 64-bit");
		}
		else {
			$struct_sz = 24;
			::rptMsg("Win2K3/Vista/Win2K8, 32-bit");
		}
	}
	
	foreach my $i (0..($num_entries - 1)) {
		my $struct = substr($data,(8 + ($struct_sz * $i)),$struct_sz);
		if ($struct_sz == 24) {
			my ($len,$max_len,$ofs,$t0,$t1,$f0,$f1) = unpack("vvVVVVV",$struct);
			
			my $file = substr($data,$ofs,$len);
			$file =~ s/\00//g;
			$file =~ s/^\\\?\?\\//;
			my $t = ::getTime($t0,$t1);
			$files{$i}{filename} = $file;
			$files{$i}{modtime} = $t;
#			$files{$file}{size} = $f0 if (($f1 == 0) && ($f0 > 3));
			$files{$i}{executed} = 1 if (($f0 < 4) && ($f0 & 0x2));
		}
		elsif ($struct_sz == 32) {
			my ($len,$max_len,$padding,$ofs0,$ofs1,$t0,$t1,$f0,$f1) = unpack("vvVVVVVVV",$struct);
			my $file = substr($data,$ofs0,$len);
			$file =~ s/\00//g;
			$file =~ s/^\\\?\?\\//;
			my $t = ::getTime($t0,$t1);
			$files{$i}{filename} = $file;
			$files{$i}{modtime} = $t;
			$files{$i}{size} = $f0 if (($f1 == 0) && ($f0 > 3));
			$files{$i}{executed} = 1 if (($f0 < 4) && ($f0 & 0x2));
		}
		else {
#
		}
	}
}

#-----------------------------------------------------------
# appWin7()
# parse Win2k8R2, Win7 data
#-----------------------------------------------------------
sub appWin7 {
	my $data = shift;
	my $struct_sz = 0;
	my $num_entries = unpack("V",substr($data,4,4));
#	::rptMsg("Num_entries: ".$num_entries);
# 128-byte header	
	my ($len,$max_len,$padding) = unpack("vvV",substr($data,128,8));
	if (($max_len - $len) == 2) {
		if ($padding == 0) {
			$struct_sz = 48;
			::rptMsg("Win2K8R2/Win7, 64-bit");
		}
		else {
			$struct_sz = 32;
			::rptMsg("Win2K8R2/Win7, 32-bit");
		}
	}

	foreach my $i (0..($num_entries - 1)) {
		my $struct = substr($data,(128 + ($struct_sz * $i)),$struct_sz);
		if ($struct_sz == 32) {
			my ($len,$max_len,$ofs,$t0,$t1,$f0,$f1) = unpack("vvV5x8",$struct);
			my $file = substr($data,$ofs,$len);
			$file =~ s/\00//g;
			$file =~ s/^\\\?\?\\//;
			my $t = ::getTime($t0,$t1);
 			$files{$i}{filename} = $file;	
			$files{$i}{modtime} = $t;
			$files{$i}{executed} = 1 if ($f0 & 0x2);
		}
		else {
			my ($len,$max_len,$padding,$ofs0,$ofs1,$t0,$t1,$f0,$f1) = unpack("vvV7x16",$struct);
			my $file = substr($data,$ofs0,$len);
			$file =~ s/\00//g;
			$file =~ s/^\\\?\?\\//;
			my $t = ::getTime($t0,$t1);
 			$files{$i}{filename} = $file;	
			$files{$i}{modtime} = $t;
			$files{$i}{executed} = 1 if ($f0 & 0x2);
		}
	}
}

#-----------------------------------------------------------
# appWin8()
#-----------------------------------------------------------
sub appWin8 {
	my $data = shift;
	my $len = length($data);
	my ($jmp, $t0, $t1, $sz, $name);
	my $ct = 0;
	my $ofs = unpack("V",substr($data,0,4));
	
	while($ofs < $len) {
		my $tag = unpack("V",substr($data,$ofs,4));
# 32-bit		
		if ($tag == 0x73746f72) {
			$jmp = unpack("V",substr($data,$ofs + 8,4));
			($t0,$t1) = unpack("VV",substr($data,$ofs + 12,8));
			$sz = unpack("v",substr($data,$ofs + 20,2));
			$name = substr($data,$ofs + 22,$sz);
			$name =~ s/\00//g;
			$files{$ct}{filename} = $name;
			$files{$ct}{modtime} = ::getTime($t0,$t1);
			$ct++;
			$ofs += ($jmp + 12);
		}
# 64-bit
		elsif ($tag == 0x73743030 || $tag == 0x73743031) {
			$jmp = unpack("V",substr($data,$ofs + 8,4));
			$sz = unpack("v",substr($data,$ofs + 0x0C,2));
			$name = substr($data,$ofs + 0x0E,$sz + 2);
			$name =~ s/\00//g;
			($t0,$t1) = unpack("VV",substr($data,($ofs + 0x0E + $sz +2 + 8),8));
			$files{$ct}{filename} = $name;
			$files{$ct}{modtime} = ::getTime($t0,$t1);
			$ct++;
			$ofs += ($jmp + 12);
		}		
		else {
# Unknown tag
		}			
	
	}
}

#-----------------------------------------------------------
# appWin81()
# 
#-----------------------------------------------------------
sub appWin81 {
	my $data = shift;
	my $len = length($data);
	my ($tag, $sz, $t0, $t1, $name, $name_len);
	my $ct = 0;
#	my $ofs = unpack("V",substr($data,0,4));
	my $ofs = 0x80;
	
	while ($ofs < $len) {
		$tag = substr($data,$ofs,4);
		if ($tag eq "10ts" || $tag eq "00ts") {
			
			$sz = unpack("V",substr($data,$ofs + 0x08,4));
			$name_len   = unpack("v",substr($data,$ofs + 0x0c,2));
			my $name      = substr($data,$ofs + 0x0e,$name_len);
			$name =~ s/\00//g;
#			($t0,$t1) = unpack("VV",substr($data,$ofs + 0x03 + $name_len,8));
			($t0,$t1) = unpack("VV",substr($data,$ofs + 0x0e + $name_len + 0x0a,8));
			$files{$ct}{filename} = $name;
			$files{$ct}{modtime} = ::getTime($t0,$t1);

			$ct++;
			$ofs += ($sz + 0x0c);
		}
	}
}

#-----------------------------------------------------------
# appWin10()
# Ref: http://binaryforay.blogspot.com/2015/04/appcompatcache-changes-in-windows-10.html
#-----------------------------------------------------------
sub appWin10 {
	my $data = shift;
	my $len = length($data);
	my ($tag, $sz, $t0, $t1, $name, $name_len);
	my $ct = 0;
	my $ofs = unpack("V",substr($data,0,4));
#	my $ofs = 0x30;
	
	while ($ofs < $len) {
		$tag = substr($data,$ofs,4);
		if ($tag eq "10ts") {
			
			$sz = unpack("V",substr($data,$ofs + 0x08,4));
			$name_len   = unpack("v",substr($data,$ofs + 0x0c,2));
			my $name      = substr($data,$ofs + 0x0e,$name_len);
			$name =~ s/\00//g;
#			($t0,$t1) = unpack("VV",substr($data,$ofs + 0x03 + $name_len,8));
			($t0,$t1) = unpack("VV",substr($data,$ofs + 0x0e + $name_len,8));
			$files{$ct}{filename} = $name;
			$files{$ct}{modtime} = ::getTime($t0,$t1);
			$ct++;
			$ofs += ($sz + 0x0c);
		}
	}
}

#-----------------------------------------------------------
# alertCheckPath()
#-----------------------------------------------------------
sub alertCheckPath {
	my $path = shift;
	$path = lc($path);
	my @alerts = ("recycle","globalroot","temp","system volume information","appdata",
	              "application data");
	
	foreach my $a (@alerts) {
		if (grep(/$a/,$path)) {
			::alertMsg("ALERT: appcompatcache: ".$a." found in path: ".$path);              
		}
	}
}

#-----------------------------------------------------------
# alertCheckADS()
#-----------------------------------------------------------
sub alertCheckADS {
	my $path = shift;
	my @list = split(/\\/,$path);
	my $last = $list[scalar(@list) - 1];
	::alertMsg("ALERT: appcompatcache: Poss. ADS found in path: ".$path) if grep(/:/,$last);
}

1;