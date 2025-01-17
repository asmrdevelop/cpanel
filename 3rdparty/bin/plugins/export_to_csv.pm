#!/usr/local/cpanel/3rdparty/bin/perl
#-----------------------------------------------------------------------------
# Export To CSV AWStats plugin
# This plugin adds export to csv functionality for different stats data
#
# Copyright (c) 2005 Pim Snel for Lingewoud B.V. 

# This AWStats plugin is a free software distributed under the GNU General 
# Public License. 
#-----------------------------------------------------------------------------
# Perl Required Modules: None
#-----------------------------------------------------------------------------
# This plugin does not work when Tooltips are loaded or any other plugin that
# uses the debug function.
#
# TODO
# 1. make all year work
# 2. add more export types
# 3. cleanup code
# 4. fix htmlentities?
#
# $Id$

# <-----
# ENTER HERE THE USE COMMAND FOR ALL REQUIRED PERL MODULES.
# ----->

use strict;no strict "refs";
use HTML::Entities;

#-----------------------------------------------------------------------------
# PLUGIN VARIABLES
#-----------------------------------------------------------------------------
# <-----
# ENTER HERE THE MINIMUM AWSTATS VERSION REQUIRED BY YOUR PLUGIN
# AND THE NAME OF ALL FUNCTIONS THE PLUGIN MANAGE.
my $PluginNeedAWStatsVersion="6.9";
my $PluginHooksFunctions="BuildFullHTMLOutput TabHeadHTML";
# ----->

# <-----
# IF YOUR PLUGIN NEED GLOBAL VARIABLES, THEY MUST BE DECLARED HERE.
use vars qw/
$fld_termd $fld_enclosed $fld_escaped $ln_termd
$MAXLINE $max_v $max_p $max_h $max_k
$total_u $total_v $total_p $total_h $total_k
$average_nb $average_u $average_v $average_p $average_h $average_k
$total_e $total_x 
$rest_p $rest_e $rest_k $rest_x
$firstdaytoshowtime $lastdaytoshowtime
$firstdaytocountaverage $lastdaytocountaverage
/;
# ----->

$fld_termd=',';
$fld_enclosed='"';
$fld_escaped='\\';
$ln_termd="\n";


#-----------------------------------------------------------------------------
# PLUGIN FUNCTION: Init_pluginname
#-----------------------------------------------------------------------------
sub Init_export_to_csv {
	my $InitParams=shift;
	my $checkversion=&Check_Plugin_Version($PluginNeedAWStatsVersion);

	#$EXPORTCSVON=1;

	if ($QueryString =~ /exportcsv=([^&]+)/i)
	{ 
		print "Content-type: application/csv\n";
		print "Content-disposition: attachment; filename=filex.csv\n";
		print "\n";
		$HeaderHTTPSent=1;
		%HTMLOutput=();
		$NOHTML=1;
	}

	return ($checkversion?$checkversion:"$PluginHooksFunctions");
}



#-----------------------------------------------------------------------------
# PLUGIN FUNTION: AddHTMLBodyHeader_pluginname
# UNIQUE: NO (Several plugins using this function can be loaded)
# Function called to Add HTML code at beginning of BODY section.
#-----------------------------------------------------------------------------
sub AddHTMLBodyHeader_export_to_csv {
	return 1;
}

#-----------------------------------------------------------------------------
# PLUGIN FUNTION: BuildFullHTMLOutput_pluginname
# UNIQUE: NO (Several plugins using this function can be loaded)
# Function called to output an HTML page completely built by plugin instead
# of AWStats output
#-----------------------------------------------------------------------------
sub BuildFullHTMLOutput_export_to_csv {

	if ($QueryString =~ /exportcsv=([^&]+)/i)
	{
		my $exportaction=$1;

		#FIXME this must be done by awstats.pl
		%MonthNumLib = ("01","$Message[60]","02","$Message[61]","03","$Message[62]","04","$Message[63]","05","$Message[64]","06","$Message[65]","07","$Message[66]","08","$Message[67]","09","$Message[68]","10","$Message[69]","11","$Message[70]","12","$Message[71]");

		# Check year and month parameters
		if ($QueryString =~ /(^|&)month=(year)/i) { error("month=year is a deprecated option. Use month=all instead."); }

		if ($QueryString =~ /(^|&)year=(\d\d\d\d)/i) { $YearRequired=sprintf("%04d",$2); }
		else { $YearRequired="$nowyear"; }

		if ($QueryString =~ /(^|&)month=(\d{1,2})/i) { $MonthRequired=sprintf("%02d",$2); }
		elsif ($QueryString =~ /(^|&)month=(all)/i) { $MonthRequired='all'; }
		else { $MonthRequired="$nowmonth"; }

		if($exportaction eq 'monthhistory')
		{
			&CSVmonths();
		}
		elsif($exportaction eq 'pageurl')
		{
			&CSVpageurl();	
		}
		elsif($exportaction eq 'monthdays')
		{
			&CSVmonthdays();	
		}
		return 1;
	}
}

sub CSVmonthdays {

	&Read_History_With_TmpUpdate($YearRequired,$MonthRequired,0,0,"day");				# Read full history file
	#
	# Define firstdaytocountaverage, lastdaytocountaverage, firstdaytoshowtime, lastdaytoshowtime
	my $firstdaytocountaverage=$nowyear.$nowmonth."01";				# Set day cursor to 1st day of month
	my $firstdaytoshowtime=$nowyear.$nowmonth."01";					# Set day cursor to 1st day of month
	my $lastdaytocountaverage=$nowyear.$nowmonth.$nowday;			# Set day cursor to today
	my $lastdaytoshowtime=$nowyear.$nowmonth."31";					# Set day cursor to last day of month
	if ($MonthRequired eq 'all') {
		$firstdaytocountaverage=$YearRequired."0101";				# Set day cursor to 1st day of the required year
	}
	if (($MonthRequired ne $nowmonth && $MonthRequired ne 'all') || $YearRequired ne $nowyear) {
		if ($MonthRequired eq 'all') {
			$firstdaytocountaverage=$YearRequired."0101";			# Set day cursor to 1st day of the required year
			$firstdaytoshowtime=$YearRequired."1201";				# Set day cursor to 1st day of last month of required year
			$lastdaytocountaverage=$YearRequired."1231";			# Set day cursor to last day of the required year
			$lastdaytoshowtime=$YearRequired."1231";				# Set day cursor to last day of last month of required year
		}
		else {
			$firstdaytocountaverage=$YearRequired.$MonthRequired."01";	# Set day cursor to 1st day of the required month
			$firstdaytoshowtime=$YearRequired.$MonthRequired."01";		# Set day cursor to 1st day of the required month
			$lastdaytocountaverage=$YearRequired.$MonthRequired."31";	# Set day cursor to last day of the required month
			$lastdaytoshowtime=$YearRequired.$MonthRequired."31";		# Set day cursor to last day of the required month
		}
	}

	# BY DAY OF MONTH
	#---------------------------------------------------------------------
	if ($Debug) { debug("ShowDaysOfMonthStats",2); }

	my $title="$Message[138]";

	$average_nb=$average_u=$average_v=$average_p=$average_h=$average_k=0;
	$total_u=$total_v=$total_p=$total_h=$total_k=0;
	# Define total and max
	$max_v=$max_h=$max_k=0;		# Start from 0 because can be lower than 1
	foreach my $daycursor ($firstdaytoshowtime..$lastdaytoshowtime) {
		$daycursor =~ /^(\d\d\d\d)(\d\d)(\d\d)/;
		my $year=$1; my $month=$2; my $day=$3;
		if (! DateIsValid($day,$month,$year)) { next; }			# If not an existing day, go to next
		$total_v+=$DayVisits{$year.$month.$day}||0;
		$total_p+=$DayPages{$year.$month.$day}||0;
		$total_h+=$DayHits{$year.$month.$day}||0;
		$total_k+=$DayBytes{$year.$month.$day}||0;
		if (($DayVisits{$year.$month.$day}||0) > $max_v)  { $max_v=$DayVisits{$year.$month.$day}; }
		#if (($DayPages{$year.$month.$day}||0) > $max_p)  { $max_p=$DayPages{$year.$month.$day}; }
		if (($DayHits{$year.$month.$day}||0) > $max_h)   { $max_h=$DayHits{$year.$month.$day}; }
		if (($DayBytes{$year.$month.$day}||0) > $max_k)  { $max_k=$DayBytes{$year.$month.$day}; }
	}
	# Define average
	foreach my $daycursor ($firstdaytocountaverage..$lastdaytocountaverage) {
		$daycursor =~ /^(\d\d\d\d)(\d\d)(\d\d)/;
		my $year=$1; my $month=$2; my $day=$3;
		if (! DateIsValid($day,$month,$year)) { next; }			# If not an existing day, go to next
		$average_nb++;											# Increase number of day used to count
		$average_v+=($DayVisits{$daycursor}||0);
		$average_p+=($DayPages{$daycursor}||0);
		$average_h+=($DayHits{$daycursor}||0);
		$average_k+=($DayBytes{$daycursor}||0);
	}
	if ($average_nb) {
		$average_v=$average_v/$average_nb;
		$average_p=$average_p/$average_nb;
		$average_h=$average_h/$average_nb;
		$average_k=$average_k/$average_nb;
		if ($average_v > $max_v) { $max_v=$average_v; }
		#if ($average_p > $max_p) { $max_p=$average_p; }
		if ($average_h > $max_h) { $max_h=$average_h; }
		if ($average_k > $max_k) { $max_k=$average_k; }
	}
	else {
		$average_v="?";
		$average_p="?";
		$average_h="?";
		$average_k="?";
	}
	#
	# Show data array for days
	print "$Message[4]";
	print $fld_termd;
	if ($ShowDaysOfMonthStats =~ /V/i) { print decode_entities($Message[10]); }
	print $fld_termd;
	if ($ShowDaysOfMonthStats =~ /P/i) { print decode_entities($Message[56]); }
	print $fld_termd;
	if ($ShowDaysOfMonthStats =~ /H/i) { print decode_entities($Message[57]); }
	print $fld_termd;
	if ($ShowDaysOfMonthStats =~ /B/i) { print decode_entities($Message[75]); }
	print $ln_termd;

	foreach my $daycursor ($firstdaytoshowtime..$lastdaytoshowtime) {
		$daycursor =~ /^(\d\d\d\d)(\d\d)(\d\d)/;
		my $year=$1; my $month=$2; my $day=$3;
		if (! DateIsValid($day,$month,$year)) { next; }			# If not an existing day, go to next
		my $dayofweekcursor=DayOfWeek($day,$month,$year);
		print "".(! $StaticLinks && $day==$nowday && $month==$nowmonth && $year==$nowyear?'':'');
		print Format_Date("$year$month$day"."000000",2);
		print (! $StaticLinks && $day==$nowday && $month==$nowmonth && $year==$nowyear?'':'');
		print "";
		print $fld_termd;
		if ($ShowDaysOfMonthStats =~ /V/i) { print "",$DayVisits{$year.$month.$day}?$DayVisits{$year.$month.$day}:"0",""; }
		print $fld_termd;
		if ($ShowDaysOfMonthStats =~ /P/i) { print "",$DayPages{$year.$month.$day}?$DayPages{$year.$month.$day}:"0",""; }
		print $fld_termd;
		if ($ShowDaysOfMonthStats =~ /H/i) { print "",$DayHits{$year.$month.$day}?$DayHits{$year.$month.$day}:"0",""; }
		print $fld_termd;
		if ($ShowDaysOfMonthStats =~ /B/i) { print "",Format_Bytes(int($DayBytes{$year.$month.$day}||0)),""; }
		print $ln_termd;
	}
#		# Average row
#		print "<tr bgcolor=\"#$color_TableBGRowTitle\"><td>$Message[96]</td>";
#		if ($ShowDaysOfMonthStats =~ /V/i) { print "<td>$average_v</td>"; }
#		if ($ShowDaysOfMonthStats =~ /P/i) { print "<td>$average_p</td>"; }
#		if ($ShowDaysOfMonthStats =~ /H/i) { print "<td>$average_h</td>"; }
#		if ($ShowDaysOfMonthStats =~ /B/i) { print "<td>$average_k</td>"; }
#		print "</tr>\n";		
#		# Total row
#		print "<tr bgcolor=\"#$color_TableBGRowTitle\"><td>$Message[102]</td>";
#		if ($ShowDaysOfMonthStats =~ /V/i) { print "<td>$total_v</td>"; }
#		if ($ShowDaysOfMonthStats =~ /P/i) { print "<td>$total_p</td>"; }
#		if ($ShowDaysOfMonthStats =~ /H/i) { print "<td>$total_h</td>"; }
#		if ($ShowDaysOfMonthStats =~ /B/i) { print "<td>".Format_Bytes($total_k)."</td>"; }
#		print "</tr>\n";		
#		print "</table>\n<br />";
}


sub CSVpageurl {

#	for (my $ix=12; $ix>=1; $ix--) {
#		my $monthix=sprintf("%02s",$ix);
#		if ($MonthRequired eq 'all' || $monthix eq $MonthRequired) {
#			&Read_History_With_TmpUpdate($YearRequired,$monthix,0,0,"all");				# Read full history file
#			#&Read_History_With_TmpUpdate($YearRequired,$monthix,0,0,"general time");				# Read full history file
#			#		print "a";
#			#print $YearRequired;
#			#print $monthix;
#		}
#		elsif (($HTMLOutput{'main'} && $ShowMonthStats) || $HTMLOutput{'alldays'}) {
#			&Read_History_With_TmpUpdate($YearRequired,$monthix,0,0,"all");	# Read general and time sections.
#			print "b";
#		}
#	}

	&Read_History_With_TmpUpdate($YearRequired,$MonthRequired,0,0,"sider");				# Read full history file

	my $title=''; my $cpt=0;
	$title=$Message[19]; $cpt=(scalar keys %_url_p);
	print "$Message[102]: $cpt $Message[28]";
	print $fld_termd;
	if ($ShowPagesStats =~ /P/i) { print decode_entities($Message[29]); }
	print $fld_termd;
	if ($ShowPagesStats =~ /B/i) { print decode_entities($Message[106]); }
	print $fld_termd;
	if ($ShowPagesStats =~ /E/i) { print decode_entities($Message[104]); }
	print $fld_termd;
	if ($ShowPagesStats =~ /X/i) { print decode_entities($Message[116]); }
	print $fld_termd;
	print $ln_termd;

	$total_p=$total_k=$total_e=$total_x=0;
	my $count=0;
	&BuildKeyList($MaxRowsInHTMLOutput,$MinHit{'File'},\%_url_p,\%_url_p); 
	$max_p=1; $max_k=1;

	foreach my $key (@keylist) {
		if ($_url_p{$key} > $max_p) { $max_p = $_url_p{$key}; }
		if ($_url_k{$key}/($_url_p{$key}||1) > $max_k) { $max_k = $_url_k{$key}/($_url_p{$key}||1); }
	}
	foreach my $key (@keylist) {
		print $key;
		print $fld_termd;
		my $bredde_p=0; my $bredde_e=0; my $bredde_x=0; my $bredde_k=0;
		if ($max_p > 0) { $bredde_p=int($BarWidth*($_url_p{$key}||0)/$max_p)+1; }
		if (($bredde_p==1) && $_url_p{$key}) { $bredde_p=2; }
		if ($max_p > 0) { $bredde_e=int($BarWidth*($_url_e{$key}||0)/$max_p)+1; }
		if (($bredde_e==1) && $_url_e{$key}) { $bredde_e=2; }
		if ($max_p > 0) { $bredde_x=int($BarWidth*($_url_x{$key}||0)/$max_p)+1; }
		if (($bredde_x==1) && $_url_x{$key}) { $bredde_x=2; }
		if ($max_k > 0) { $bredde_k=int($BarWidth*(($_url_k{$key}||0)/($_url_p{$key}||1))/$max_k)+1; }
		if (($bredde_k==1) && $_url_k{$key}) { $bredde_k=2; }
		if ($ShowPagesStats =~ /P/i) { print "$_url_p{$key}"; }
		print $fld_termd;
		if ($ShowPagesStats =~ /B/i) { print "".($_url_k{$key}?Format_Bytes($_url_k{$key}/($_url_p{$key}||1)):" ").""; }
		print $fld_termd;
		if ($ShowPagesStats =~ /E/i) { print "".($_url_e{$key}?$_url_e{$key}:" ").""; }
		print $fld_termd;
		if ($ShowPagesStats =~ /X/i) { print "".($_url_x{$key}?$_url_x{$key}:" ").""; }
		print $fld_termd;
		$total_p += $_url_p{$key};
		$total_e += $_url_e{$key};
		$total_x += $_url_x{$key};
		$total_k += $_url_k{$key};
		$count++;
		print $ln_termd;
	}
	$rest_p=$TotalPages-$total_p;
	$rest_k=$TotalBytesPages-$total_k;
	$rest_e=$TotalEntries-$total_e;
	$rest_x=$TotalExits-$total_x;
	if ($rest_p > 0 || $rest_e > 0 || $rest_k > 0) {
		print "$Message[2]";
		print $fld_termd;
		if ($ShowPagesStats =~ /P/i) { print "".($rest_p?$rest_p:" ").""; }
		print $fld_termd;
		if ($ShowPagesStats =~ /B/i) { print "".($rest_k?Format_Bytes($rest_k/($rest_p||1)):" ").""; }
		print $fld_termd;
		if ($ShowPagesStats =~ /E/i) { print "".($rest_e?$rest_e:" ").""; }
		print $fld_termd;
		if ($ShowPagesStats =~ /X/i) { print "".($rest_x?$rest_x: "").""; }
		print $fld_termd;
		print $ln_termd;
	}
}

# BY MONTH
#---------------------------------------------------------------------
sub CSVmonths {

	$MonthRequired="all";
	# Loop on each month of year
	for (my $ix=12; $ix>=1; $ix--) {
		my $monthix=sprintf("%02s",$ix);
		if ($MonthRequired eq 'all' || $monthix eq $MonthRequired) {
			&Read_History_With_TmpUpdate($YearRequired,$monthix,0,0,"all");				# Read full history file
			#&Read_History_With_TmpUpdate($YearRequired,$monthix,0,0,"general time");				# Read full history file
		}
#		elsif (($HTMLOutput{'main'} && $ShowMonthStats) || $HTMLOutput{'alldays'}) {
#			&Read_History_With_TmpUpdate($YearRequired,$monthix,0,0,"general time");	# Read general and time sections.
#			print "b";
#		}
	}

	my $title="$Message[162]";

	$average_nb=$average_u=$average_v=$average_p=$average_h=$average_k=0;
	$total_u=$total_v=$total_p=$total_h=$total_k=0;

	$max_v=$max_p=$max_h=$max_k=1;
	# Define total and max
	for (my $ix=1; $ix<=12; $ix++) {
		my $monthix=sprintf("%02s",$ix);
		$total_u+=$MonthUnique{$YearRequired.$monthix}||0;
		$total_v+=$MonthVisits{$YearRequired.$monthix}||0;
		$total_p+=$MonthPages{$YearRequired.$monthix}||0;
		$total_h+=$MonthHits{$YearRequired.$monthix}||0;
		$total_k+=$MonthBytes{$YearRequired.$monthix}||0;
		#if (($MonthUnique{$YearRequired.$monthix}||0) > $max_v) { $max_v=$MonthUnique{$YearRequired.$monthix}; }
		if (($MonthVisits{$YearRequired.$monthix}||0) > $max_v) { $max_v=$MonthVisits{$YearRequired.$monthix}; }
		#if (($MonthPages{$YearRequired.$monthix}||0) > $max_p)  { $max_p=$MonthPages{$YearRequired.$monthix}; }
		if (($MonthHits{$YearRequired.$monthix}||0) > $max_h)   { $max_h=$MonthHits{$YearRequired.$monthix}; }
		if (($MonthBytes{$YearRequired.$monthix}||0) > $max_k)  { $max_k=$MonthBytes{$YearRequired.$monthix}; }
	}

	# Show data array for month
	if ($AddDataArrayMonthStats) {
		print "$Message[5]";
		print $fld_termd;
		if ($ShowMonthStats =~ /U/i) { print decode_entities($Message[11]); }
		print $fld_termd;
		if ($ShowMonthStats =~ /V/i) { print decode_entities($Message[10]); }
		print $fld_termd;
		if ($ShowMonthStats =~ /P/i) { print decode_entities($Message[56]); }
		print $fld_termd;
		if ($ShowMonthStats =~ /H/i) { print decode_entities( $Message[57]); }
		print $fld_termd;
		if ($ShowMonthStats =~ /B/i) { print decode_entities($Message[75]); }
		print $fld_termd;

		print $ln_termd;

		for (my $ix=1; $ix<=12; $ix++) {
			my $monthix=sprintf("%02s",$ix);
			print (! $StaticLinks && $monthix==$nowmonth && $YearRequired==$nowyear?'':'');
			print "$MonthNumLib{$monthix} $YearRequired";
			print (! $StaticLinks && $monthix==$nowmonth && $YearRequired==$nowyear?'':'');
			print $fld_termd;
			if ($ShowMonthStats =~ /U/i) { print "",$MonthUnique{$YearRequired.$monthix}?$MonthUnique{$YearRequired.$monthix}:"0",""; }
			print $fld_termd;
			if ($ShowMonthStats =~ /V/i) { print "",$MonthVisits{$YearRequired.$monthix}?$MonthVisits{$YearRequired.$monthix}:"0",""; }
			print $fld_termd;
			if ($ShowMonthStats =~ /P/i) { print "",$MonthPages{$YearRequired.$monthix}?$MonthPages{$YearRequired.$monthix}:"0",""; }
			print $fld_termd;
			if ($ShowMonthStats =~ /H/i) { print "",$MonthHits{$YearRequired.$monthix}?$MonthHits{$YearRequired.$monthix}:"0",""; }
			print $fld_termd;
			if ($ShowMonthStats =~ /B/i) { print "",Format_Bytes(int($MonthBytes{$YearRequired.$monthix}||0)),""; }
			print $ln_termd;
		}
	}
}

#------------------------------------------------------------------------------
# Function:     Return the string to add in html tag to include popup javascript code
# Parameters:   $title
# Input:        None
# Output:       None
# Return:       string with javascript code
#------------------------------------------------------------------------------
sub TabHeadHTML_export_to_csv {
	my $title=shift;
	my $export_section;

	if(substr($title,0,length($Message[128])) eq $Message[128])
	{
		#$export_section="monthsummary";
	}
	elsif(substr($title,0,length($Message[162])) eq $Message[162])
	{
		$export_section="monthhistory";
	}
	elsif(substr($title,0,length($Message[19])) eq $Message[19])
	{
		$export_section="pageurl";
	}
	elsif(substr($title,0,length($Message[138])) eq $Message[138])
	{
		$export_section="monthdays";
	}


	if($export_section)
	{
		#return ($EXPORTCSVON?"&nbsp;&nbsp;&nbsp;-&nbsp;&nbsp;&nbsp;<a href=\"awstats.pl?pluginmode=export_to_csv&month=$MonthRequired&year=$YearRequired&framename=mainright&exportcsv=$export_section\">Export CSV</a>":"");
		return ("&nbsp;&nbsp;&nbsp;-&nbsp;&nbsp;&nbsp;<a href=\"awstats.pl?pluginmode=export_to_csv&month=$MonthRequired&year=$YearRequired&framename=mainright&exportcsv=$export_section\">Export CSV</a>");
	}
	else
	{
		return '';
	}
}


1;	# Do not remove this line
