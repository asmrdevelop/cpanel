#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/statmanager.cgi    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::ArrayFunc::Uniq        ();
use Cpanel::PwCache                ();
use Cpanel::PwCache::PwEnt         ();
use Cpanel::CleanupStub            ();
use Cpanel::Config::CpUserGuard    ();
use Cpanel::Config::CpConfGuard    ();
use Cpanel::Config::LoadCpConf     ();
use Cpanel::Config::LoadConfig     ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Config::HasCpUserFile  ();
use Cpanel::Config::Users          ();
use Cpanel::Encoder::Tiny          ();
use Cpanel::Form                   ();
use Cpanel::Locale ('lh');
use Cpanel::Logd::LagCheck        ();
use Cpanel::OSSys                 ();
use Cpanel::PwCache               ();
use Cpanel::SafeFile              ();
use Cpanel::SafeRun::Simple       ();
use Cpanel::Server::Type::License ();
use Cpanel::Signal                ();
use Cpanel::SysQuota              ();
use Whostmgr::ACLS                ();
use Whostmgr::HTMLInterface       ();

*safehtml = *Cpanel::Encoder::Tiny::safe_html_encode_str;

Whostmgr::ACLS::init_acls();

print "Content-type: text/html\n\n";

Whostmgr::HTMLInterface::defheader( lh()->maketext('Statistics Software Configuration'), '', '/cgi/statmanager.cgi', undef, undef, undef, undef, undef, 'statistics_software_configuration' );

if ( !Whostmgr::ACLS::hasroot() || !Cpanel::Server::Type::License::is_cpanel() ) {
    print <<'EOM';

<div><h1>Permission denied</h1></div>

EOM
    Whostmgr::HTMLInterface::deffooter();

    exit;
}

my $cpconf_ref     = Cpanel::Config::LoadCpConf::loadcpconf();
my $self           = 'statmanager.cgi';
my %FORM           = Cpanel::Form::parseform();
my $security_token = $ENV{'cp_security_token'} || '';

$Cpanel::IxHash::Modify = 'angle_bracket_encode';

my @LOGGERS = qw(webalizer awstats analog);
my @dfcache;

print <<EOM;
<style>
#page{
    margin: 0px 10px;
}
.genlist {
    border: 1px solid #eee;
    margin: 0 0 15px;
}
.genlist th {
    background: #eee;
    padding: 5px 7px;
}

.genlist td {
    border: 1px solid #eee;
    padding: 5px;
    text-align: center;
}
#boxcontain{
    width: 100%;
    min-height: 150px;
    display: block;
}
#boxcontain2{
    width: 100%;
    min-height: 150px;
    display: block;
}
.left {
    float: left;
    width: 49%;
}
#leftbox {
    float: left;
    width: 90%;
}
.right {
    float: right;
    width: 49%;
}
#rightbox {
    float: left;
    width: 90%;
}
.bottom{
    float: left;
    width: 100%;
}
legend {
    font-size: 129%;
    font-weight: bold;
}
fieldset {
    border: 1px solid #ccc;
    margin: 10px 0;
    padding: 10px 20px;
}
.clear {display: block; overflow: hidden;}
.clearer {clear: both;}

.tdshadered {
   background-color: #FFAAAA;
   border: 1px solid #eee;
   padding: 5px;
   text-align: center;
}

.tdshadegreen {
   background-color: #AAFFAA;
   border: 1px solid #eee;
   padding: 5px;
   text-align: center;
}

.dlcellheader {
    background: #eee;
    padding: 5px 7px;
}

.botcellline {
   border-bottom: 2px #999999 solid;
}
</style>
<br />
EOM

#defaults added by nick@cpanel.net
if ( $cpconf_ref->{'skipanalog'} eq '' )    { $cpconf_ref->{'skipanalog'}    = 0; }
if ( $cpconf_ref->{'skipwebalizer'} eq '' ) { $cpconf_ref->{'skipwebalizer'} = 0; }
if ( $cpconf_ref->{'skipawstats'} eq '' )   { $cpconf_ref->{'skipawstats'}   = 1; }
if ( $cpconf_ref->{'keepstatslog'} eq '' )  { $cpconf_ref->{'keepstatslog'}  = 0; }

@LOGGERS = sort @LOGGERS;

# Default Action

print "<div id=\"page\">";
if ( $FORM{'cgiaction'} eq '' ) {
    printForm();
}
elsif ( $FORM{'cgiaction'} eq 'explain' ) {
    explainConfig();
}
elsif ( $FORM{'cgiaction'} eq 'configprocesstimes' ) {
    configProcessTimes();
}
elsif ( $FORM{'cgiaction'} eq 'changehours' ) {
    changehours();
}
elsif ( $FORM{'cgiaction'} eq 'biguserstatstatus' ) {
    biguserstatstatus();
}
elsif ( $FORM{'cgiaction'} eq 'procuserstats' ) {
    procuserstats();
}

# NickN mod: no cpbackup logs
elsif ( $FORM{'cgiaction'} eq 'backlogs' ) {
    saveCpbackuplogs();
    printForm();
}

# Modify Runnable Programs and Default Generators
elsif ( $FORM{'cgiaction'} eq 'modprogs' ) {
    modifyPrograms();
    printForm();
}

# Switch to user permission view
elsif ( $FORM{'cgiaction'} eq 'modusers' ) {
    printUserForm();
}

# Delete a user from the ACL
elsif ( $FORM{'cgiaction'} eq 'deleteuser' ) {
    my $ret = deleteUser( $FORM{'user'} );
    if    ( $ret == 0 ) { print '<h2>User Removed.</h2>'; }
    elsif ( $ret == 1 ) { print '<h2>Invalid User.</h2>'; }
    elsif ( $ret == 2 ) {
        print '<h2>User not found in allowed user list.</h2>';
    }
    printUserForm();
}

# Delete ALL users from the ACL
elsif ( $FORM{'cgiaction'} eq 'deleteall' ) {
    deleteAllUsers();
    print '<h2>All Users Removed</h2>';
    printUserForm();
}

# Add A User to the ACL
elsif ( $FORM{'cgiaction'} eq 'adduser' ) {
    my $ret = addUser( $FORM{'user'} );
    if    ( $ret == 0 ) { print '<h2>User Added.</h2>'; }
    elsif ( $ret == 1 ) { print '<h2>Unable to add user.</h2>'; }
    printUserForm();
}

# Add ALL Users to the ACL
elsif ( $FORM{'cgiaction'} eq 'addall' ) {
    addAllUsers();
    printUserForm();
}

# Show user configuration screen.
elsif ( $FORM{'cgiaction'} eq 'showuser' ) {
    my $ret = Cpanel::PwCache::getpwnam( $FORM{'user'} );

    # Fail for root and invalid users.
    if ($ret) {
        printConfigForm();
    }
    else {
        print '<h2>Invalid User.</h2>';
        printUserForm();
    }
}

# Configure a User in the ACL
elsif ( $FORM{'cgiaction'} eq 'confuser' ) {
    configureUser();
    printUserForm();
}
elsif ( $FORM{'cgiaction'} eq 'changecycle' ) {
    changeCycle();
}
elsif ( $FORM{'cgiaction'} eq 'allowall' ) {
    allowAll();
    printForm();
}
else {
    print q{<h2>You actioned.. And I don't know how to handle it.</h2>};
}

Whostmgr::HTMLInterface::deffooter();

##############################################################################
#
##############################################################################
sub printForm {
    my %LAGGED;
    try {
        %LAGGED = Cpanel::Logd::LagCheck::get_lagging_stats_users_and_lag_times();
    }
    catch {
        print qq[<div>WARNING: $_</div>];
    };

    my $stats_conf_ref = loadStatsConf();
    my @defaults       = split( /,/, $stats_conf_ref->{'DEFAULTGENS'} );

    print qq{<script type="text/javascript" src="/js/sorttable.js"></script>};

    #Stats Summary Box
    print qq{<div class="clear">};
    print qq{<div class="left">};
    print qq{<fieldset>};
    print qq{<legend>Statistics Status Summary</legend>};

    if (%LAGGED) {
        print qq{<b><font color="#FF0000">The server is having trouble keeping up with your statistics processing schedule.  You should increase the time between statistic generation, or upgrade the server.  If you have recently decreased the time between statistic generation, you may wish to wait that amount of time to see if the server will catch up before changing back.</b></font><br>\n};

        if ( $FORM{'showusers'} eq '1' ) {
            print qq{<br /><a href="$self">Hide which users are behind</a><br /><br />};
            print qq{<table class="sortable genlist"><tr><th><b>User</b></th><th><b>Minutes Behind</b></th></tr>\n};
            foreach my $user ( sort { $LAGGED{$a} <=> $LAGGED{$b} } keys %LAGGED ) {
                my $minbehind = sprintf( '%.2f', int( $LAGGED{$user} / 60 ) );
                print qq{<tr><td>$user</td><td>$minbehind</td></tr>\n};
            }
            print "</table>\n";
        }
        else {
            print qq{<br /><a href="$self?showusers=1">Show which users are behind</a>\n};
        }
    }
    else {
        print qq{<b><font color="#00aa00">The server currently is able to keep up with your statistics processing schedule.</font></b><br>\n};
    }
    print << "EOM";
<p>
<br /><h2>See Specific User's Statistics Summary</h2>
<form action="$self" method="POST">
    <input type="hidden" name="cgiaction" value="biguserstatstatus">
    User to Display: <select name="user" align=top>
        <option value="all">all</option>
EOM

    my @userlist = Cpanel::Config::Users::getcpusers();
    foreach my $userName ( sort @userlist ) {
        print "<option value=\"$userName\">$userName</option>";
    }

    print << "EOM";
 </select>
 <input type="submit" class="btn-primary" value="Go"></td>
</form>
</p>
EOM
    print qq{</fieldset>};
    print qq{</div>};
    print <<"EOM";
    <div class="right">
        <fieldset>
            <legend>Process Statistics for User</legend>
<p>
<h2>Process Specific User's Statistics</h2>
<form action="$self" method="POST">
    <input type="hidden" name="cgiaction" value="procuserstats">
    User to Process: <select name="user" align=top>
EOM

    foreach my $userName ( sort @userlist ) {
        print "<option value=\"$userName\">$userName</option>";
    }

    print << "EOM";
 </select>
 <input type="submit" class="btn-primary" value="Go"></td>
</form>
</p>
        </fieldset>
    </div>
    </div>
EOM

    print << "EOM";
        <div class="clear left" id="left">
            <fieldset>
                <legend>Generators Configuration</legend>
                <form action=${self} method=POST>
                    <input type=hidden name=cgiaction value=modprogs>
                    <table class="sortable genlist" id="genlist">
                        <tr>
                            <th>Generator</th>
                            <th>Available to Users</th>
                            <th>Active by Default</th>
                        </tr>
EOM
    my %active_loggers = map { $_ => ( $cpconf_ref->{ 'skip' . lc($_) } == 0 ) ? 1 : 0 } @LOGGERS;

    my $has_active = 0;
    foreach my $val ( values %active_loggers ) {
        $has_active += $val;
    }

    foreach my $log (@LOGGERS) {
        print "<tr><td>", ucfirst($log), "</td>";
        print "<td><input type=checkbox name=perm", lc($log);
        if ( $cpconf_ref->{ 'skip' . lc($log) } == 0 ) { print " CHECKED"; }
        print "></td>";
        if ($has_active) {
            next if !$active_loggers{$log};
            my $lc_log  = lc $log;
            my $checked = ( grep( /^${log}$/i, @defaults ) ) ? 'checked' : '';
            print qq{<td><input type="checkbox" name="$lc_log" $checked /></td>\n};
        }
        else {
            print "<td>&nbsp;</td>";
        }
        print "</tr>";
    }
    print "</table>";
    if ( $active_loggers{'awstats'} ) {
        my $allow_awstats_include = $stats_conf_ref->{'allow_awstats_include'} ? 'checked' : '';
        print qq{<input value="1" type="checkbox" name="allow_awstats_include" $allow_awstats_include />&nbsp;Allow Awstats configuration Include file<br />\n};
        print qq{Awstats Include file option will allow a user defined configuration file to be included at the time of statistics processesing. The include file should be placed in the user's home directory at ~/tmp/awstats/awstats.conf.include. This file can be used to override and add new configuration options to Awstats.<br />};
    }
    print "<br /><input class='btn-primary' type=submit value=Save></form>";
    print "<br />";
    print "</fieldset></div>";

    #User Permissions Block
    print "<div class=\"right\">";
    print qq{<fieldset>};
    print qq{<legend>User Permissions</legend>};

    # Allow specific users to change their web gen software
    print qq{<form action="$self" method="POST">};
    print "<input name=\"cgiaction\" value=\"modusers\" type=\"hidden\" />";
    print "Choose which specific users can modify their web generating software.";
    print "<blockquote><input class=\"btn-primary\" value=\"Choose Users\" type=\"submit\"></blockquote>";
    print "</form>";

    # Allow all users to change their web gen software
    print qq{<form action="$self" method="POST">};
    print "<input name=\"cgiaction\" value=\"allowall\" type=\"hidden\" />";
    my $checked = ( ( exists $stats_conf_ref->{'ALLOWALL'} && $stats_conf_ref->{'ALLOWALL'} eq 'yes' ) ? ' checked="checked"' : '' );
    print qq{<input type="checkbox" name="allowall" value="yes" $checked><input type=hidden name=cgiaction value=modusers />\n};
    print " Allow <strong>all</strong> users to change their web statistics generating software.";
    print "<blockquote><input class='btn-primary' type=submit value=Save /></blockquote>";
    print "</form>";

    print qq{</fieldset>};
    print <<"EOM";
    </div>
   <br />
EOM

    print qq{</div>};
    print qq{<div class="clearer">&nbsp;</div>};

    print qq{<div id="boxcontain2">};

    #Statistics Processing Configuration Summary Box
    print <<"EOM";
   <div class="left">
   <fieldset>
   <legend>Schedule Summary</legend>
EOM
    my $stats_time   = $cpconf_ref->{'cycle_hours'};
    my $bwstats_time = $cpconf_ref->{'bwcycle'};
    my $wait_time    = $cpconf_ref->{'cycle_hours'} * 1.5;
    print "<table class=\"sortable genlist\" width=\"300px\">";
    print "<tr><th>Stat Type</th><th>Updated</th></tr>";
    print "<tr><td>Web Traffic Statistics</td><td>every $stats_time hours</td></tr>";
    print "<tr><td>Bandwidth Statistics</td><td>every $bwstats_time hours</td></tr>";
    print "</table>";
    print "<br /> If you wish to compare data from each
      statistics program you should only compare data that is at least
      <b>$wait_time</b> hours old to ensure that it has been updated
      and is providing the correct information.  Please note these times are
      estimates, and are subject to change based on the amount of traffic on
      the server.";
    print "</fieldset>";
    print "<br>";
    print "</div>";

    #Statistics Processing Configuration
    print <<"EOM";
<div id ="bottom" class="right">
<fieldset>
    <legend>Schedule Configuration</legend>
    <fieldset>
        <legend>Log Processing Frequency</legend>
        <form action="$self" method="POST">
            <input type="hidden" name="cgiaction" value="changecycle">
            Process log files every <input size="5" type="text" name="Hcycle" value="$stats_time"> hours.  <input type="submit" class="btn-primary" value="Change">
        </form>
    </fieldset>
    <fieldset>
        <legend>Bandwidth Processing Frequency</legend>
        <form action="$self" method="POST">
            <input type="hidden" name="cgiaction" value="changecycle">
            Process bandwidth every <input size="5" type="text" name="BWcycle" value="$bwstats_time"> hours.  <input type="submit" class="btn-primary" value="Change">
        </form>
    </fieldset>
    <fieldset>
        <legend>Statistics Schedule</legend>
        <td>
            <form action="$self" method="POST">
            <input type="hidden" name="cgiaction" value="configprocesstimes">
            <input type="submit" class="btn-primary" value="Configure Statistic Process Time Schedule">
            </form>
        </td>
    </fieldset>
</fieldset>
<br />
</div>
</div>
EOM
}

##############################################################################
#
##############################################################################
sub printUserForm {
    my $stats_conf_ref = loadStatsConf();

    print qq{<script language="javascript">};
    print "function fillConfig() { document.conf.user.value = document.acl.user.options[document.acl.user.selectedIndex].value; } ";
    print "</script>";

    print << "EOM";
    <h3>Choose which users can modify their statistical software<h3>
    <p>Any users in the <i>Allowed</i> list will be able to select which statistical software programs they use from within their cPanel interface.</p>
EOM
    print "<div class=\"actions\" style=\"width:500px\;\">";
    print "<table width=400 cellspacing=0 cellpadding=2 border=0>";
    print "<tr><td width=\"175\"><b>Allowed Users</b></td><td width=50>&nbsp;</td><td width=\"175\"><b>Available Users</b></td></tr>";
    print "<tr><td>";

    # Allowed Users Box, and Delete
    print "<form action=${self} name='acl' method=POST>";
    print "<input type=hidden name=cgiaction value='deleteuser'>";
    print "<select name='user' size=7 align=top onChange='fillConfig();'>";
    foreach my $user ( sort split( /,/, $stats_conf_ref->{'VALIDUSERS'} ) ) {
        my $html_safe_user = Cpanel::Encoder::Tiny::safe_html_encode_str($user);
        print "<option value='${html_safe_user}'>${html_safe_user}</option>";
    }
    print "</select><br /><br /><input class='btn-primary' type=submit value='Remove'></form>";
    print "<form action=${self} method=POST><input type=hidden name=cgiaction value='deleteall'>";
    print "<input class='btn-primary' type=submit Value='Remove All'></form>";
    print "</td></td><td valign=middle><b><---></b></td><td>";

    # All users box, and Add
    print "<form action=${self} method=POST>";
    print "<input type=hidden name=cgiaction value=adduser>";
    print "<select size=7 name='user'>";
    my @userlist = Cpanel::Config::Users::getcpusers();
    print join( "\n", map { "<option name='$_' value='$_'>$_</option>" } sort @userlist );
    print "</select><br /><br />";
    print "<input class='btn-primary' type=submit value=Add></form>";
    print "<form action=${self} method=POST><input type=hidden name=cgiaction value=addall>";
    print "<input class='btn-primary' type=submit value='Add All'></form>";
    print "</td></tr>";
    print "</table>";
    print "</div>";

    # Configure User.
    print "<br />";
    print "<form action=${self} method=POST name='conf'><input type=hidden name=cgiaction value=showuser>";
    print "Choose Specific Stats Programs for: <input type=text value='' name='user'>";
    print "<input class='btn-primary' type=submit value='Configure'></form>";
    print "<br />";
    print "<br />";
    print "<br />";
    print " <div align=\"center\"><b>[ <a href='${self}'>Go Back</a> ]</b></div>";
}

##############################################################################
#
##############################################################################
sub printConfigForm {

    my $cpuser_ref =
        Cpanel::Config::HasCpUserFile::has_cpuser_file( $FORM{'user'} )
      ? Cpanel::Config::LoadCpUserFile::loadcpuserfile( $FORM{'user'} )
      : {};

    my @loggers = ();
    if ( defined( $cpuser_ref->{'STATGENS'} ) ) {
        @loggers = split( /,/, $cpuser_ref->{'STATGENS'} );
    }
    else {
        my $stats_conf_ref = loadStatsConf();
        @loggers = split( /,/, $stats_conf_ref->{'DEFAULTGENS'} );
    }
    print "<form action=${self} method=POST>";
    print "<input type=hidden name=cgiaction value=confuser>";
    print "<input type=hidden name=user value='", $FORM{'user'}, "'>";
    print "<h2>Choose Specific Stats Programs for $FORM{'user'}</h2><p>Here you can specify which stats programs $FORM{'user'} can use.</p>";
    print "<ul class=\"actions\" style=\"width:200px\">";
    foreach my $log (@LOGGERS) {
        if ( $cpconf_ref->{ 'skip' . $log } == 0 ) {
            my $string = "<input type=checkbox name='${log}'";
            if ( grep( /^${log}$/i, @loggers ) ) { $string .= " CHECKED"; }
            $string .= ">";
            print "$string ", ucfirst($log), " <br />";
        }
    }
    print "<br /><div align=\"center\"><input class='btn-primary' type=Submit Value=Save></div>";
    print "</form></ul>";

    print "<br>";
    print "<br>";
    print "<br>";
    print " <b>[ <a href='${self}?cgiaction=modusers'>Go Back</a> ]</b>";
    return;
}

##############################################################################
#
##############################################################################
sub loadStatsConf {
    return load_Config('/etc/stats.conf');
}

##############################################################################
#
##############################################################################
sub deleteUser {
    my $user = shift;

    return 1 if ( !$user );

    my $stats_conf_ref = loadStatsConf();

    my @users = split( /,/, $stats_conf_ref->{'VALIDUSERS'} );
    if ( !grep( /^\Q${user}\E$/, @users ) ) { return 2; }
    my @newusers = grep( !/^\Q${user}\E$/i, @users );

    $stats_conf_ref->{'VALIDUSERS'} = join( ',', @newusers );

    flushConfig( $stats_conf_ref, '/etc/stats.conf' );

    return 0;
}

#############################################################################
#
#############################################################################
sub deleteAllUsers {
    my $stats_conf_ref = loadStatsConf();

    # Easy Removal...
    $stats_conf_ref->{'VALIDUSERS'} = '';

    flushConfig( $stats_conf_ref, '/etc/stats.conf' );
}

##############################################################################
#
##############################################################################
sub addUser {
    my $user = shift;

    return 1 if ( !$user );
    return 1 if ( !Cpanel::PwCache::getpwnam( $FORM{'user'} ) );

    my $stats_conf_ref = loadStatsConf();
    my @users          = grep( !/^\Q${user}\E$/, split( /\,/, $stats_conf_ref->{'VALIDUSERS'} ) );

    push @users, $user;
    $stats_conf_ref->{'VALIDUSERS'} = join( ',', @users );

    flushConfig( $stats_conf_ref, '/etc/stats.conf' );

    return 0;
}

##############################################################################
#
##############################################################################
sub addAllUsers {
    my @users          = Cpanel::Config::Users::getcpusers();
    my $stats_conf_ref = loadStatsConf();

    my @cusers = split( /\,/, $stats_conf_ref->{'VALIDUSERS'} );

    push @cusers, @users;

    $stats_conf_ref->{'VALIDUSERS'} = join( ',', Cpanel::ArrayFunc::Uniq::uniq(@cusers) );

    flushConfig( $stats_conf_ref, '/etc/stats.conf' );

    return 0;
}

##############################################################################
#
##############################################################################
sub allowAll {
    my $stats_conf_ref = loadStatsConf();

    $stats_conf_ref->{'ALLOWALL'} = ( lc( $FORM{'allowall'} ) eq 'yes' ? 'yes' : 'no' );

    flushConfig( $stats_conf_ref, '/etc/stats.conf' );

    return;
}

##############################################################################
#
##############################################################################
sub modifyPrograms {
    require Whostmgr::TweakSettings;

    Whostmgr::TweakSettings::load_module('Main');

    my $cpconf_guard = Cpanel::Config::CpConfGuard->new();
    foreach my $log (@LOGGERS) {
        my $logname = 'perm' . $log;
        my $old_val = $cpconf_ref->{ 'skip' . $log };
        $cpconf_ref->{ 'skip' . $log } = $cpconf_guard->{'data'}->{ 'skip' . $log } = ( $FORM{$logname} eq 'on' ? 0 : 1 );
        my $new_val = $cpconf_ref->{ 'skip' . $log };
        if ( exists $Whostmgr::TweakSettings::Main::Conf{ 'skip' . $log }->{'action'} ) {
            &{ $Whostmgr::TweakSettings::Main::Conf{ 'skip' . $log }->{'action'} }( $new_val, $old_val );
        }
    }

    $cpconf_guard->save();

    my @defaults = ();
    foreach my $log (@LOGGERS) {
        if ( $FORM{$log} eq 'on' ) {
            push @defaults, uc($log);
        }
    }
    my $stats_conf_ref = loadStatsConf();

    $stats_conf_ref->{'DEFAULTGENS'} = join( ',', @defaults );

    if ( $#defaults == -1 ) { $stats_conf_ref->{'DEFAULTGENS'} = 0; }

    if ( $FORM{'allow_awstats_include'} ) {
        $stats_conf_ref->{'allow_awstats_include'} = 1;
    }
    else {
        $stats_conf_ref->{'allow_awstats_include'} = 0;
    }

    flushConfig( $stats_conf_ref, "/etc/stats.conf" );

    restartCpanelLogd();
    restartCpsrvd();

    return;
}

##############################################################################
#
##############################################################################
sub restartCpanelLogd {
    require Cpanel::Signal;
    Cpanel::Signal::send_hup_cpanellogd();

    print "<font color=\"#FF0000\">cpanellogd Reloaded.</font><br />";
    return;
}

##############################################################################
#
##############################################################################
sub restartCpsrvd {
    Cpanel::Signal::send_hup_cpsrvd();

    print "<font color=\"#FF0000\">cpsrvd Reloaded.</font><br />";
    return;
}

##############################################################################
#
##############################################################################
sub configureUser {
    return 1 if ( !$FORM{'user'} );
    my $cpuser_guard = Cpanel::Config::CpUserGuard->new( $FORM{'user'} );
    my @loggers      = ();
    foreach my $log (@LOGGERS) {
        if ( lc( $FORM{$log} ) eq 'on' ) {
            push @loggers, uc($log);
        }
    }
    $cpuser_guard->{'data'}->{'STATGENS'} = join( ',', @loggers );

    $cpuser_guard->save();
    print "<h2>User Updated</h2>";
    return;
}

####################################################
#
####################################################
sub changehours {
    return if !Whostmgr::ACLS::hasroot();

    my @hours          = ();
    my $stats_conf_ref = load_Config("/etc/stats.conf");

    for my $i ( 0 .. 23 ) {
        if ( defined( $FORM{$i} ) && lc( $FORM{$i} ) eq "yes" ) {
            push @hours, $i;
        }
    }
    my $hours_str = join( ",", @hours );

    $stats_conf_ref->{'BLACKHOURS'} = $hours_str;

    # Write hours out to file.
    flushConfig( $stats_conf_ref, '/etc/stats.conf' );

    if ( $#hours >= 15 ) { handleBlackout( $#hours + 1 ); }
    print "<fieldset><legend>Log Schedule Results</legend>";
    restartCpanelLogd();
    print "</fieldset>";
    print " <b>[ <a href='${self}'>Go Back</a> ]</b>";
    return;
}

sub changeCycle {
    return if !Whostmgr::ACLS::hasroot();

    my $cpconf_guard = Cpanel::Config::CpConfGuard->new();
    if ( defined $FORM{'Hcycle'} && $FORM{'Hcycle'} =~ m/\S/ ) {
        if ( $FORM{'Hcycle'} =~ m/^\d*(?:\.(?:[05]0?|[27]5))?$/ && $FORM{'Hcycle'} <= 5000 ) {
            $cpconf_ref->{'cycle_hours'} = $cpconf_guard->{'data'}->{'cycle_hours'} = $FORM{'Hcycle'};
        }
        else {
            print "<font color=\"#FF0000\">Error: Please enter a number between 0.25 and 5000. You must set the interval in increments of 0.25 (or 15 minutes).</font><br />";
        }
    }
    if ( defined( $FORM{'BWcycle'} ) && $FORM{'BWcycle'} =~ m/\S/ ) {
        if ( $FORM{'BWcycle'} =~ m/^\d*(?:\.(?:[05]0?|[27]5))?$/ ) {
            if ( 0 == $FORM{'BWcycle'} ) {

                # use the default value of 2
                $cpconf_ref->{'bwcycle'} = $cpconf_guard->{'data'}->{'bwcycle'} = 2;
                print "<font color=\"#FF0000\">Error: Bandwidth processing value of 0 hours not allowed, defaulting to 2.</font><br />";
            }
            elsif ( $FORM{'BWcycle'} <= 24 ) {
                $cpconf_ref->{'bwcycle'} = $cpconf_guard->{'data'}->{'bwcycle'} = $FORM{'BWcycle'};
            }
            else {
                $cpconf_ref->{'bwcycle'} = $cpconf_guard->{'data'}->{'bwcycle'} = 24;
                print "<font color=\"#FF0000\">Error: Bandwidth processing must be at least once per day.</font><br />";
            }
        }
        else {
            print "<font color=\"#FF0000\">Error: Please enter a number between 0.25 and 24. You must set the interval in increments of 0.25 (or 15 minutes). </font><br />";
        }
    }
    $cpconf_guard->save();

    restartCpanelLogd();
    printForm();

    return;
}

##############################################################################
#
##############################################################################
sub handleBlackout {
    my ($hours) = @_;
    print "<fieldset><legend>Warning</legend>\n";
    print "<b>You have selected ${hours} hours for logs <font color=#FF0000><u><b>NOT</b></u></font> to be run. ";
    print "This may not leave enough time for stats to be processed. ";
    print "If you would like to modify these settings, please use your ";
    print "back button, and reselect the hours you would like stats to not be processed.";
    print "</b></fieldset><br/>\n";
    return;
}

##############################################################################
#   load_Config - Parses the given file which should be hold key/value pairs
#     one pair per line of the format, Key=Value
#     The returned hash is a representation of that file.
##############################################################################

sub configProcessTimes {
    print "<fieldset><legend>Statistics Processing Times</legend>";
    my $stats_conf_ref = load_Config("/etc/stats.conf");
    my @hours          = split( /,/, $stats_conf_ref->{'BLACKHOURS'} );
    my $cycle_hrs      = ( defined( $cpconf_ref->{'cycle_hours'} ) ) ? $cpconf_ref->{'cycle_hours'} : 0;
    print "Check all hours that you would like log analysis <font color=#ff0000><u><b>NOT</b></u></font> to be performed.<br /><br />";

    print "<form action=${self} method=POST>\n";
    print "<input type=hidden name=cgiaction value=changehours>\n";
    print "<table width=80% cellspacing=0 cellpadding=0 border=1>\n";
    my $bg = "2";
    for my $i ( 0 .. 5 ) {
        print "<tr class='tdshade$bg'>";
        for my $j ( 0 .. 3 ) {
            my $ni = ( $j * 6 ) + $i;
            print "<td><input type=checkbox name='$ni' value='yes'";
            if ( grep( /^${ni}$/, @hours ) ) { print " CHECKED"; }
            print "> ";
            if ( $ni < 10 ) { print "0"; }
            print "$ni:00</td>";
        }
        print "</tr>";
        if   ( $bg eq "2" ) { $bg = "1"; }
        else                { $bg = "2"; }
    }
    print "</table>";
    print "<br /><i>Note: Keep in mind that if there isn't enough time allocated to running ";
    print "log analysis, your logs may never fully be completely analyzed.</i>\n";
    print "<blockquote><input class='btn-primary' type=submit value='Save'></blockquote>";
    print "</form>";
    print "</fieldset>";

################ NickN added code ##############
    print "<fieldset><legend>Additional Options</legend>";
    print "<form action=${self} method=POST>";
    print "<input type=hidden name=cgiaction value=backlogs>";
    print "<input type=checkbox name=cpbackuplogs value='yes' ";
    if ( $cpconf_ref->{'nocpbackuplogs'} == 1 ) { print "CHECKED"; }
    print ">";
    print " Prevent cpanellogd (Log Processing) and cpbackup (Backups) from running at same time.<br /><br /> <i>If checked, make sure to set times that do not overlap for backups and log processing.</i>";
    print "<blockquote><input class='btn-primary' type=submit value='Save'></blockquote>";
    print "</form>";
    print "</fieldset>";
################################################

    print "<br><br><br>";
    print " <div align=\"center\"><b>[ <a href='${self}'>Go Back</a> ]</b></div>";
    return;
}

############### NickN added code ################
sub saveCpbackuplogs {
    my $cpconf_guard = Cpanel::Config::CpConfGuard->new();

    if ( lc( $FORM{'cpbackuplogs'} ) eq 'yes' ) {
        $cpconf_ref->{'nocpbackuplogs'} = $cpconf_guard->{'data'}->{'nocpbackuplogs'} = 1;
    }
    else {
        $cpconf_ref->{'nocpbackuplogs'} = $cpconf_guard->{'data'}->{'nocpbackuplogs'} = 0;
    }

    $cpconf_guard->save();

    print "<h2>Configuration Saved.</h2>";
    restartCpanelLogd();
    return;
}
################################################

sub procuserstats {
    return if ( !$FORM{'user'} );
    return if ( $FORM{'user'} =~ /\W/ );
    if ( fork() ) {
        print "<h4 style='color: red;'>Processing user statistics for " . Cpanel::Encoder::Tiny::safe_html_encode_str( $FORM{'user'} ) . " in the background.</h4>\n";
        printForm();
        return;
    }
    else {
        Cpanel::OSSys::setsid();
        Cpanel::CleanupStub::daemonclosefds();
        open( STDIN,  '<', '/dev/null' ) or die "Cannot redirect STDIN to /dev/null";
        open( STDOUT, '>', '/dev/null' ) or die "Cannot redirect STDOUT to /dev/null";
        open( STDERR, '>', '/dev/null' ) or die "Cannot redirect STDERR to /dev/null";
        exec( '/usr/local/cpanel/scripts/runweblogs', $FORM{'user'} );    #connect directly to stdout but keep going if we die
        exit;
    }
    return;
}

sub biguserstatstatus {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my $stats_conf_ref = loadStatsConf();
    my @defaults       = split( /,/, $stats_conf_ref->{'DEFAULTGENS'} );
    my @users          = split( /,/, $stats_conf_ref->{'VALIDUSERS'} );
    my $now            = time();
    my (%DISABLED);
    my (%DEFAULT);
    print "<Br>";
    my ( $qrused, $qrlimit ) = Cpanel::SysQuota::analyzerepquotadata();

    foreach my $log (@LOGGERS) {
        if ( $cpconf_ref->{ 'skip' . lc($log) } != 0 ) { $DISABLED{$log} = 1; }
        if ( grep( /^${log}$/i, @defaults ) )          { $DEFAULT{$log}  = 1; }
    }

    print "<div align=\"center\"> <b>[ <a href='${self}'>Go Back</a> ]</b></div><br />";
    print "<h3>Legend:</h3>";
    print "<table width=\"400\"><tr><td><img src=/check.gif align=absmiddle>: Stats Enabled</td><td><img src=/images/disk.gif align=absmiddle>: Disk Quota Exceeded</td><td><img src=/images/redx.gif align=absmiddle>: Stats Disabled</td></tr></table>";
    my $lag          = 0;
    my $cycleseconds = ( 60 * 60 * $cpconf_ref->{'cycle_hours'} );
    Cpanel::PwCache::PwEnt::setpwent();

    my $disk_threshold = exists $cpconf_ref->{'statthreshhold'} ? $cpconf_ref->{'statthreshhold'} : 256;

    while ( my @PW = Cpanel::PwCache::PwEnt::getpwent() ) {
        my $user    = $PW[0];
        my $homedir = $PW[7];

        next if !Cpanel::Config::HasCpUserFile::has_cpuser_file($user);
        next if ( $FORM{'user'} ne 'all' && $FORM{'user'} ne $user );
        my $statlag = 0;

        my $disk_remain   = $qrlimit->{$user} ? ( $qrlimit->{$user} - $qrused->{$user} ) : 'unlimited';
        my $lastruntime   = ( stat("/var/cpanel/lastrun/$user/stats") )[9];
        my $lastrunbwtime = ( stat("/var/cpanel/lastrun/$user/bandwidth") )[9];

        if ( ( $lastruntime + ( $cycleseconds * 2 ) ) < $now ) {
            $lag     = ( ( $now - ( $lastruntime - ( $cycleseconds * 2 ) ) ) / 60 );
            $statlag = 1;
        }
        if ( !$lastruntime ) { $lag = 'an unknown number of'; }

        # Protected above
        my $cpuser_ref  = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
        my $main_domain = $cpuser_ref->{'DOMAIN'};
        my @ADNS        = @{ $cpuser_ref->{'DOMAINS'} };
        my $allowedgens = $cpuser_ref->{'STATGENS'} || '';
        my (%USERCONF);
        if ( $stats_conf_ref->{'ALLOWALL'} eq 'yes' ) {
            open( SCC, '<', $homedir . '/tmp/stats.conf' );
            while (<SCC>) {
                chomp();
                my ( $stat, $value ) = split( /=/, $_,    2 );
                my ( $gen,  $dom )   = split( /-/, $stat, 2 );
                $USERCONF{ lc($dom) }{ lc($gen) } = lc($value);
            }
            close(SCC);
        }

        my @userchablegens;
        if ($allowedgens) {
            @userchablegens = split( /,/, $allowedgens );
        }
        else {
            @userchablegens = @LOGGERS;
        }

        print "<table class=dlcellheader width=97% ><tr><td>";
        print "<table width=100% cellspacing=0 cellpadding=2>";

        print "<tr><td class=botcellline><b>$user</b></td>
         <td class=botcellline >Stats Last Processed at:<br>" . localtime($lastruntime) . "</td>
         <td class=botcellline >Bandwidth Last Processed at:<br>" . localtime($lastrunbwtime) . "</td>";
        print "<td class=botcellline>";
        if ($statlag) { print "<font color=#ff0000><b>Stats Processing is Behind " . sprintf( "%.2f", ${lag} ) . " minutes</b></font>"; }
        else          { print "<font color=#00aa00>Stats Processing is keeping up</font>"; }
        print "</td></tr>";
        my $tdwidth = ( 100 / ( $#LOGGERS + 2 ) ) . "%";
        print "<tr><td width=$tdwidth></td>";

        foreach my $log (@LOGGERS) {
            print "<td width=$tdwidth ><b>${log}</b></td>";
        }
        print "</tr>";
        my @DISPLAY_DOMAINS = ( $main_domain, @ADNS );

        foreach my $dns ( sort @DISPLAY_DOMAINS ) {
            print "<tr>";
            my @dnsstring = split( //, $dns );
            my $i         = 0;
            my $dnsS;
            foreach (@dnsstring) {
                $i++;
                $dnsS .= $_;
                if ( $i % 20 == 0 ) {
                    $dnsS .= "<WBR>";
                }
            }
            print "<td wrap><b>${dnsS}</b></td>";
            foreach my $log (@LOGGERS) {

                my $user_has_perm = grep( /^\Q$user\E$/i, @users ) && grep( /^\Q$log\E$/i, @userchablegens ) ? 1 : undef;

                if ( $disk_remain ne 'unlimited' && $disk_remain < $disk_threshold ) {
                    print "<td align=center class=tdshadered><img src=/images/redx.gif align=absmiddle> <img src=/images/disk.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . "&gen=" . $log . "&status=D&reason=Q";
                }
                else {
                    if ( $DISABLED{$log} ) {
                        print "<td align=center class=tdshadered><img src=/images/redx.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . "&gen=" . $log . "&status=D&reason=A";
                    }
                    else {
                        if (
                            $stats_conf_ref->{'ALLOWALL'} ne 'yes'
                            && (   !grep( /^\Q$user\E$/i, @users )
                                || !grep( /^\Q$log\E$/i, @userchablegens ) )
                        ) {
                            if ( $DEFAULT{$log} ) {
                                print "<td align=center class=tdshadegreen><img src=/check.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . "&gen=${log}&status=E&reason=G";
                            }
                            elsif ($user_has_perm) {
                                if ( $USERCONF{$dns}{$log} eq 'no' ) {
                                    print "<td align=center class=tdshadered><img src=/images/redx.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . '&gen=' . $log . '&status=D&reason=CU';
                                }
                                elsif ( $USERCONF{$dns}{$log} eq 'yes' ) {
                                    print "<td align=center class=tdshadegreen><img src=/check.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . '&gen=' . $log . '&status=E&reason=CU';
                                }
                                else {
                                    print "<td align=center class=tdshadered><img src=/images/redx.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . "&gen=" . $log . "&status=D&reason=NU";
                                }
                            }
                            else {
                                print "<td align=center class=tdshadered><img src=/images/redx.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . "&gen=${log}&status=D&reason=G";
                            }
                            if ( !$user_has_perm ) {
                                print "O";
                            }
                            if ( ( !grep( /^\Q$log\E$/i, @userchablegens ) ) ) {
                                print "F";
                            }
                            if ( ( !grep( /^\Q$user\E$/i, @users ) ) ) {
                                print "P";
                            }
                        }
                        else {
                            if ( $USERCONF{$dns}{$log} eq 'no' ) {
                                print "<td align=center class=tdshadered><img src=/images/redx.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . '&gen=' . $log . '&status=D&reason=C';
                            }
                            elsif ( $USERCONF{$dns}{$log} eq 'yes' ) {
                                print "<td align=center class=tdshadegreen><img src=/check.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . '&gen=' . $log . '&status=E&reason=C';
                            }
                            else {
                                if ( $DEFAULT{$log} ) {
                                    print "<td align=center class=tdshadegreen><img src=/check.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . "&gen=" . $log . "&status=E&reason=GN";
                                }
                                else {
                                    print "<td align=center class=tdshadered><img src=/images/redx.gif align=absmiddle> <a href=\"${self}?cgiaction=explain&user=" . $user . "&dns=" . $dns . "&gen=" . $log . "&status=D&reason=GN";
                                }
                            }
                        }
                    }
                }
                print "\"><b>Details</b></a></td>\n";
            }
            print "</tr>\n";
        }
        print "</table>";
        print "</td></tr></table><br>";

    }
    Cpanel::PwCache::PwEnt::endpwent();

    # Go Back..
    print "<br>";
    print "<div align=\"center\"> <b>[ <a href='${self}'>Go Back</a> ]</b></div>";
    return;
}

sub explainConfig {
    my $user      = safehtml( $FORM{'user'} );
    my $dns       = safehtml( $FORM{'dns'} );
    my $status    = safehtml( $FORM{'status'} );
    my $gen       = safehtml( $FORM{'gen'} );
    my @reasons   = split( //, $FORM{'reason'} );
    my $statustxt = '<font color=#00cc000>enabled</font>';
    if ( $status eq "D" ) {
        $statustxt = '<font color=#ff0000>disabled</font>';
    }
    print "<fieldset><legend>${gen} status for ${dns}</legend>";
    print "<p>${gen} is <b>${statustxt}</b> on the domain ${dns} because:";
    print "<ul>";
    foreach (@reasons) {
        print "<li>";
        if ( $_ eq "Q" ) {
            print "${user}'s Disk Quota has or is about to be exceeded.";
            print " <b><a target=_blank href=\"${security_token}/scripts/quotalist?domain=${dns}&user=${user}\">Change</a></b>";
        }
        elsif ( $_ eq "A" ) {
            print "Global Generator Permissions have <B>${gen}</B> ${statustxt}.";
            print " <b><a href=${self}>Change</a></b>";
        }
        elsif ( $_ eq "G" ) {
            print "Global Generator Defaults have <B>${gen}</B> ${statustxt}.";
            print " <b><a href=${self}>Change</a></b>";
        }
        elsif ( $_ eq "O" ) {
            print "User ${user} is not allowed to change their statistics generator configuration.";
            print " <b><a href=${self}>Change</a></b>";
        }
        elsif ( $_ eq "F" ) {
            print "${user} is specifically forbidden from changing ${gen}'s status from the default.";
            print " <b><a href=\"${self}?cgiaction=showuser&user=${user}\">Change</a></b>";
        }
        elsif ( $_ eq "P" ) {
            print "${user} has not been given permission to change any generators status from the default.";
            print " <b><a href=\"${self}?cgiaction=modusers\">Change</a></b>";
        }
        elsif ( $_ eq "C" ) {
            print "<form id=xfer_form_C action='/xfercpanel' method='POST' target=_blank>";
            print "    <input type=hidden name='user' value=\"${user}\">";
            print "    <input type=hidden name='token' value=\"${security_token}\">";
            print "</form>";
            print "${user} has ${statustxt} this domain's ${gen} in their cPanel interface.";
            print " <b><a href=\"xfercpanel\" onclick=\"document.getElementById('xfer_form_C').submit(); return false;\" >Change</a></b>";
        }
        elsif ( $_ eq "N" ) {
            print "<form id=xfer_form_N action='/xfercpanel' method='POST' target=_blank>";
            print "    <input type=hidden name='user' value=\"${user}\">";
            print "    <input type=hidden name='token' value=\"${security_token}\">";
            print "</form>";
            print "${user} has not configured ${gen} in their cPanel interface.";
            print " <b><a href=\"xfercpanel\" onclick=\"document.getElementById('xfer_form_N').submit(); return false;\" >Change</a></b>";
        }
        elsif ( $_ eq "U" ) {
            print "${user} has been given permission to use <B>${gen}</B>.";
            print " <b><a href=${self}>Change</a></b>";
        }
        print "</li>";
    }
    print "</ul></p></fieldset>";
    print "<br>";
    print " <div align=\"center\"><b>[ <a href='${self}'>Go Back</a> ]</b></div>";
    return;
}

## case 34397 deprecation: delete this sub completely
##############################################################################
# get_mountpoint
#     Given a path to search for, get_mountpath returns a string representing
#   the device to which the path belongs.
#     ie.  get_mountpoint('/home/nirosys'); # returns '/dev/hda5'
##############################################################################
sub get_mountpoint {
    my %mount = ();
    my ($spath) = @_;

    if ( $#dfcache == -1 ) {
        @dfcache = split( /\n/, Cpanel::SafeRun::Simple::saferun("df") );
    }

    foreach (@dfcache) {
        if (/^(\/dev\/[\w\d]+)/) {
            my @fs = split(/[\s\t]+/);
            $mount{$1} = $fs[5];
        }
    }

    if ( !defined($spath) ) { return ""; }

    my $match = undef;
    foreach my $dev ( keys %mount ) {
        if ( $spath =~ /^${mount{${dev}}}/ ) {
            if    ( !defined($match) ) { $match = $dev; }
            elsif ( length( $mount{$match} ) < length( $mount{$dev} ) ) {
                $match = $dev;
            }
        }
    }
    return $match;
}

sub flushConfig {
    my ( $conf, $filename ) = @_;

    my @aconf = map( $_ . '=' . $conf->{$_}, sort keys %{$conf} );
    my $sl    = Cpanel::SafeFile::safeopen( \*CONF, '>', $filename ) || return;
    print CONF join( "\n", @aconf );
    print CONF "\n";
    Cpanel::SafeFile::safeclose( \*CONF, $sl );
    return 1;
}

sub load_Config {
    my $file    = shift;
    my $reverse = shift;
    my $conf_ref;
    $conf_ref = {} if !ref $conf_ref;
    $conf_ref = Cpanel::Config::LoadConfig::loadConfig( $file, $conf_ref, '\s*[\=]\s*', '^\s*[#]', 0, 0, { 'use_reverse' => $reverse ? 1 : 0, } );
    if ( !defined($conf_ref) ) {
        $conf_ref = {};
    }
    return wantarray ? %{$conf_ref} : $conf_ref;
}
