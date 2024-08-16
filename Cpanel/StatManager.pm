package Cpanel::StatManager;

# cpanel - Cpanel/StatManager.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 MODULE

C<Cpanel::StatManager>

=head1 DESCRIPTION

C<Cpanel::StatManager> provides implementation methods for managing the
weblog analyzers for a user and for individual domains. This module also
includes the legacy API1 calls for these same applicaitons.

=head1 SYNOPSIS
  use Cpanel::Config::LoadCpConf                  ();
  use Cpanel::Config::LoadCpUserFile::CurrentUser ();

  my $user = q/tommy/;

  my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
  my $cpuser = Cpanel::Config::LoadCpUserFile::CurrentUser::load($user);

  use Cpanel::StatManager ();

  local %Cpanel::CONF = %$cpconf;
  local %Cpanel::CPDATA = %$cpuser;
  local $Cpanel::homedir = q{/home/tommy};

  my $config = Cpanel::StatManager::get_configuration();

  if ($config->{locked}) {
      print "$user CANNOT change log analyzer settings\n";
  } else {
      print "$user can change log analyzer settings\n";
  }

  print "\nAnalyzer Common Configuration\n";
  foreach my $analyzer (@{$config->{analyzers}}) {
      print "  Analyzer: $analyzer->{name}\n";
      print "  - Enabled By Default: " . ($analyzer->{enabled_by_default} ? "Yes" : "No") . "\n";
      print "  - Available For User: " . ($analyzer->{available_for_user} ? "Yes" : "No") . "\n";
  }

  print "\nAnalyzer Domain Configuration\n";
  foreach my $domain (@{$config->{domains}}) {
      next unless $domain->{domain} =~ m/^tommy\.tld/;
      print "Domain: $domain->{domain}\n";
      foreach my $analyzer (@{$domain->{analyzers}}) {
          print "  Analyzer: $analyzer->{name}\n";
          print "  - Is Enabled By User:   " . ($analyzer->{enabled_by_user} ? "Yes" : "No") . "\n";
          print "  - Is Enabled (overall): " . ($analyzer->{enabled} ? "Yes" : "No") . "\n";
      }
  }

  my $issues = Cpanel::StatManager::save_configuration([
      {
      domain => 'tommy.tld',
      analyzers => [
          {
              name => 'awstats',
              enabled => 1,
          }
      ]
  }]);

  print" \nUpdate Domain Configuration\n";
  $config = Cpanel::StatManager::get_configuration();

  print "\nAnalyzer Domain Configuration\n";
  foreach my $domain (@{$config->{domains}}) {
      next unless $domain->{domain} =~ m/^tommy\.tld/;
      print "Domain: $domain->{domain}\n";
      foreach my $analyzer (@{$domain->{analyzers}}) {
          print "  Analyzer: $analyzer->{name}\n";
          print "  - Is Enabled By User:   " . ($analyzer->{enabled_by_user} ? "Yes" : "No") . "\n";
          print "  - Is Enabled (overall): " . ($analyzer->{enabled} ? "Yes" : "No") . "\n";
      }
  }

You should get output similar to the following:

  tommy can change log analyzer settings

  Analyzer Common Configuration
    Analyzer: awstats
    - Enabled By Default: Yes
    - Available For User: Yes
    Analyzer: webalizer
    - Enabled By Default: No
    - Available For User: Yes

  Analyzer Domain Configuration
  Domain: tommy.tld
    Analyzer: awstats
    - Is Enabled:         Yes
    - Is Enabled By User: Yes
    Analyzer: webalizer
    - Is Enabled:         Yes
    - Is Enabled By User: Yes
  Domain: wordpress.tommy.tld
    Analyzer: awstats
    - Is Enabled:         Yes
    - Is Enabled By User: Yes
    Analyzer: webalizer
    - Is Enabled:         No
    - Is Enabled By User: No

=cut

use strict;
use warnings;

use Cpanel::Exception                           ();
use Cpanel::Locale                              ();
use Cpanel::PwCache                             ();
use Cpanel::Server::Type::Role::WebServer       ();
use Cpanel::StatsManager::Configuration::System ();
use Cpanel::StatsManager::Configuration::User   ();
use Cpanel::StatsManager::Configuration::Domain ();

our $VERSION = '2.2';

my %STAT_CONFIG;
my @LOGGERS;
my @DEFAULT_LOGGERS = ();

sub StatManager_init {
    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();

    loadConfig();
    @LOGGERS = ( 'WEBALIZER', 'ANALOG', 'AWSTATS' );

    if (   exists $STAT_CONFIG{'ALLOWALL'}
        && $STAT_CONFIG{'ALLOWALL'} ne 'yes'
        && exists $Cpanel::CPDATA{'STATGENS'}
        && defined $Cpanel::CPDATA{'STATGENS'} ) {
        @LOGGERS = split( /,/, $Cpanel::CPDATA{'STATGENS'} );
        foreach my $log (@LOGGERS) {
            if ( exists $Cpanel::CONF{ 'skip' . lc($log) }
                && $Cpanel::CONF{ 'skip' . lc($log) } == 1 ) {
                @LOGGERS = grep( !/^${log}$/i, @LOGGERS );
            }
        }
    }
    else {
        for my $log (@LOGGERS) {
            if ( exists $Cpanel::CONF{ 'skip' . lc($log) }
                && $Cpanel::CONF{ 'skip' . $log } ) {
                @LOGGERS = grep( !/^${log}$/i, @LOGGERS );
            }
        }
    }

    if ( defined( $STAT_CONFIG{'DEFAULTGENS'} ) ) {
        @DEFAULT_LOGGERS = split( /,/, $STAT_CONFIG{'DEFAULTGENS'} );
    }
    else {
        @DEFAULT_LOGGERS = @LOGGERS;
    }
    return 1;
}

##########################################################
#
##########################################################
sub loadConfig {
    return if ( !-e '/etc/stats.conf' );
    if ( open my $statsconf_fh, '<', '/etc/stats.conf' ) {
        my ( $var, $val );
        while ( my $line = readline $statsconf_fh ) {
            chomp $line;
            ( $var, $val ) = split( /=/, $line );
            next if ( !defined $var || $var eq '' || !defined $val || $val eq '' );
            $STAT_CONFIG{ uc($var) } = $val;
        }
        close $statsconf_fh;
    }
    return;
}

###########################################################
#
###########################################################
sub isValid {
    return 1
      if ( exists $STAT_CONFIG{'ALLOWALL'} && $STAT_CONFIG{'ALLOWALL'} eq 'yes' );
    return 1
      if defined $STAT_CONFIG{'VALIDUSERS'}
      && grep { $_ eq $Cpanel::user } split( /\s*,\s*/, $STAT_CONFIG{'VALIDUSERS'} );
    return 0;
}

###########################################################
#
###########################################################
sub loadUserConfig {
    my $home = $Cpanel::homedir;
    my %conf;

    # Init-Configure based on the cpanel.conf values.
    my %cpconf  = %Cpanel::CONF;
    my @domains = @Cpanel::DOMAINS;
    foreach my $dom (@domains) {
        foreach my $log (@LOGGERS) {
            if ( $cpconf{ "skip" . lc($log) } == 1 ) {
                $conf{ uc($dom) }->{ uc($log) } = 'no';
            }
            elsif ( grep( /^${log}$/, @DEFAULT_LOGGERS ) ) {
                $conf{ uc($dom) }->{ uc($log) } = 'yes';
            }
        }
    }
    if ( !-e $home . "/tmp/stats.conf" ) { return %conf; }

    # Configure based on user's stats.conf
    if ( open( my $conf_fh, "<", $home . "/tmp/stats.conf" ) ) {
        while ( readline($conf_fh) ) {
            chomp();
            my ( $logdom, $val ) = split( /=/, uc($_),  2 );
            my ( $log,    $dom ) = split( /-/, $logdom, 2 );
            $conf{$dom}->{$log} = $val;
        }
    }
    return %conf;
}

=head2 _initialize_object_models()

Helper method to setup the object models for the StatsManger persistance.

=cut

sub _initialize_object_models {
    my $system_config = Cpanel::StatsManager::Configuration::System->new(
        cpconf => \%Cpanel::CONF,
    );

    my $user_config = Cpanel::StatsManager::Configuration::User->new(
        cpuser => \%Cpanel::CPDATA,
        system => $system_config,
    );

    my $domain_config = Cpanel::StatsManager::Configuration::Domain->new(
        system  => $system_config,
        user    => $user_config,
        cpuser  => \%Cpanel::CPDATA,
        homedir => $Cpanel::homedir,
    );
    return ( $system_config, $user_config, $domain_config );
}

=head2 _get_configuration(SYSTEM, USER, DOMAIN)

Helper method to get the configuration from the from the persistance systems.

=cut

sub _get_configuration {
    my ( $system_config, $user_config, $domain_config ) = @_;

    my @analyzers;
    foreach my $analyzer_name ( @{ $system_config->analyzers_enabled_on_system() } ) {
        push @analyzers, {
            name               => lc($analyzer_name),
            enabled_by_default => $system_config->is_analyzer_active_by_default($analyzer_name),
            available_for_user => $user_config->is_analyzer_available($analyzer_name),
        };
    }

    my $locked  = $user_config->can_user_manage_themself() ? 0 : 1;
    my $domains = $domain_config->domain_configuration();

    return {
        domains   => $domains,
        analyzers => \@analyzers,
        locked    => $locked,
    };
}

=head2 get_configuration

Get the collection of domain/logger configuration information.

=head3 RETURNS

A hashref with the following properties:

=over

=item analyzers

List of system level analyzer configuration where each item is a HashRef and has the following properties:

=over

=item name - string

Name of the analyzer. Must be one of: analog, awstats, or webalizer.

=item enabled_by_default -  Boolean (1|0)

When 1, the analyzer is enabled for all user by default; When 0, the analyzer is not enabled for all user by default.

=item available_for_user -  Boolean (1|0)

When 1, the analyzer is enabled for use by the current user; When 0, the analyzer is not available to the current user.

=back

=item domains - arrayref

ArrayRef of all domains and their current web log analyzer configurations. Each item is has the following HashRef structure:

=over

=item domain - string

A domain on the cPanel account.

=item analyzers - ArrayRef

List of analyzer configuration for the domain.

Each configuration is a HashRef with the following format:

=over

=item name - string

One of: analog, awstats, webalizer

=item enabled_by_user - Boolean (1|0)

When 1, the analyzer has been enabled for the domain by the user; When 0, the analyzer has not been enabled for the doamin by the current user. To see if the analyzer run when all the configurtion options are applied, see <enabled> property.

=item enabled - Boolean (1|0)

When 1, the analyzer will run for the domain; When 0, the analyzer will not run for the domain.

=back

=back

=item locked - Boolean (1|0)

1 if the analyzer cannot be managed by the user; 0 otherwise.

=back

=cut

sub get_configuration {
    _check_role_and_feature_or_die();

    my ( $system_config, $user_config, $domain_config ) = _initialize_object_models();
    return _get_configuration( $system_config, $user_config, $domain_config );
}

=head2 save_configuration(CHANGES)

Save updated log analyzer configuration for domains.

=head3 ARGUMENTS

=over

=item CHANGES - ArrayRef

List of domain/analyser configuration to change. Each config is a HashRef with the following properties:

=over

=item domain - string

The name of a domain owned by the current cpanel user.

=item analyzers - ArrayRef

List of analyzer configuration for this domains. Each item is a HashRef with the following properties:

=over

=item name - string

Name of the analyser. Must be one of: analog, awstats, or webalizer.

=item enabled - Boolean (1|0)

1 when you want to enabled the analyzer for the domain. 0 when you want to disable the analyzer for the domain.

=back

=back

=back

=head3 RETURNS

A hashref with the following properties:

=over

=item analyzers - ArrayRef

List of system level analyzer configuration where each item is a HashRef and has the following properties:

=over

=item name - string

Name of the analyzer. Must be one of: analog, awstats, or webalizer.

=item enabled_by_default -  Boolean (1|0)

When 1, the analyzer is enabled for all user by default; When 0, the analyzer is not enabled for all user by default.

=item available_for_user -  Boolean (1|0)

When 1, the analyzer is enabled for use by the current user; When 0, the analyzer is not available to the current user.

=back

=item domains - arrayref

ArrayRef of all domains and their current web log analyzer configurations. Each item is has the following HashRef structure:

=over

=item domain - string

A domain on the cPanel account.

=item analyzers - ArrayRef

List of analyzer configuration for the domain.

Each configuration is a HashRef with the following format:

=over

=item name - string

One of: analog, awstats, webalizer

=item enabled_by_user - Boolean (1|0)

When 1, the analyzer has been enabled for the domain by the user; When 0, the analyzer has not been enabled for the doamin by the current user. To see if the analyzer run when all the configurtion options are applied, see <enabled> property.

=item enabled - Boolean (1|0)

When 1, the analyzer will run for the domain; When 0, the analyzer will not run for the domain.

=back

=back

=item locked - Boolean (1|0)

1 if the analyzer cannot be managed by the user; 0 otherwise.

=item issues - ArrayRef

ArrayRef with list of issues encountered. Each item is a HashRef with the following properties:

=over

=item domain - string

Name of the domain that had the problem

=item not_owned  - Boolean (1|0)

Optional. When 1, the domain requested is not owned by the cPanel account.

=item analyzer - string

Opional. Name of the analyzer with the problem.

=item not_available - Boolean (1|0)

Optional. When 1, the analyzer requested was either not recognized, was not enabled or is not available for this user.

=back

=back

=cut

sub save_configuration {
    my $changes = shift;

    _check_role_and_feature_or_die();

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        die Cpanel::Exception::create('ForbiddenInDemoMode');
    }

    if ( !defined $changes || ref $changes ne 'ARRAY' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be an array.', ['changes'] );
    }

    if ( !@$changes ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must have at least one change.', ['changes'] );
    }

    my ( $system_config, $user_config, $domain_config ) = _initialize_object_models();

    my $issues = $domain_config->save_configuration(@$changes);

    my $config = _get_configuration( $system_config, $user_config, $domain_config );
    $config->{issues} = $issues;

    return $config;
}

###########################################################
#
###########################################################
sub StatManager_doForm {
    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();

    my $locale = Cpanel::Locale->get_handle();

    if ( isValid() != 1 ) { _showstatus(); return (); }

    my %user_conf = loadUserConfig();

    my %DISABLED;
    foreach my $log (@LOGGERS) {
        if ( $Cpanel::CONF{ 'skip' . lc($log) } != 0 ) {
            $DISABLED{$log} = 1;
        }
        else {
            $DISABLED{$log} = undef;
        }
    }

    my @display_order = sort @LOGGERS;
    my @domains       = sort @Cpanel::DOMAINS;

    if ( !$INC{'Cpanel/JSON.pm'} ) {
        eval 'require Cpanel::JSON';
    }
    print "<script>window.DISABLED_LOGGERS = " . Cpanel::JSON::SafeDump( \%DISABLED ) . ';</script>';
    print "<script>window.LOGGER_ORDER = " . Cpanel::JSON::SafeDump( [ map lc, @display_order ] ) . ';</script>';
    print "<script>window.DOMAINS = " . Cpanel::JSON::SafeDump( \@domains ) . ';</script>';

    my $lp_dom = $locale->maketext('Domain');
    print <<"EOF";
   <table class="sortable table table-striped" id="statsmgr">
      <thead><tr>
            <th width="60%">$lp_dom</th>
EOF
    foreach my $log (@display_order) {
        my $lc_log = lc $log;
        print qq{\t<th id="$lc_log-header" align="center" nonsortable="true" class="logger-header nonsortable">} . ucfirst($lc_log) . "</th>\n";
    }
    print "</tr></thead>\n";
    print "<tbody>";
    my %all_checked_for_logger = map { $DISABLED{$_} ? () : ( $_ => 1 ) } @display_order;

    foreach my $dom (@domains) {
        print qq{<tr><td>$dom</td>\n};
        foreach my $logger ( sort @display_order ) {
            if ( $DISABLED{$logger} ) {
                print qq{<td align="center" class="statsdisabled"><i class="fas fa-lock" aria-hidden="true"></i></td>\n};
            }
            else {
                my $string = qq{<td align="center"> <input type="checkbox" name="${logger}-${dom}" value="yes" };
                if ( lc( $user_conf{ uc($dom) }->{ uc($logger) } ) eq 'yes' ) {
                    $string .= 'CHECKED';
                }
                else {
                    $all_checked_for_logger{$logger} = undef;
                }
                $string .= '>';
                print $string. "</td>\n";
            }
        }
        print "</tr>";
    }
    print "</tbody>\n";
    print "</table>\n";
    print '<script>window.LOGGER_ALL_CHECKED = ' . Cpanel::JSON::SafeDump( \%all_checked_for_logger ) . ';</script>';
    print qq{<br/><br/><div align="center"><input type="submit" class="input-button" value="} . $locale->maketext('Save') . qq{"></div>\n};

    return 1;
}

###########################################################
#
###########################################################
sub StatManager_updateUserConfig {
    my ($FORM) = @_;

    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();

    my %CONFIG;
    my @domains = @Cpanel::DOMAINS;
    my $home    = $Cpanel::homedir;

    foreach my $domain (@domains) {
        foreach my $logger (@LOGGERS) {
            $CONFIG{ uc($domain) }->{ uc($logger) } = 'no';
        }
    }
    foreach my $key ( keys %$FORM ) {
        my ( $log, $dom ) = split( /-/, $key, 2 );
        $CONFIG{ uc($dom) }->{ uc($log) } = $$FORM{$key};
    }

    if ( !-d $home . "/tmp/" ) {
        print "Unable to save settings, please create $home/tmp/";
        return 0;
    }

    open( CONF, ">", $home . "/tmp/stats.conf" ) or die "Unable to open config file: $!.";
    foreach my $dom ( keys %CONFIG ) {
        foreach my $log ( keys %{ $CONFIG{$dom} } ) {
            print CONF uc($log), "-", uc($dom), "=", $CONFIG{$dom}->{$log}, "\n";
        }
    }
    close(CONF);
    print "Configuration saved successfully.";

    return 1;
}

sub _showstatus {
    my $self = $ENV{'SCRIPT_URL'};
    print <<EOM;
<style>
.tdshadered {
   background-color: #FFAAAA;
   border-top: 1px #374646 solid;
   border-left: 1px #374646 solid;
   border-right: 1px #374646 solid;
   border-bottom: 1px #374646 solid;
   font-family: verdana, arial, helvetica, sans-serif;
   font-size: 11px;
   font-weight: normal;
   -moz-border-radius: 10px;
   -moz-background-clip: padding;
}

.tdshadegreen {
   background-color: #AAFFAA;
   border-top: 1px #374646 solid;
   border-left: 1px #374646 solid;
   border-right: 1px #374646 solid;
   border-bottom: 1px #374646 solid;
   font-family: verdana, arial, helvetica, sans-serif;
   font-size: 11px;
   font-weight: normal;
   -moz-border-radius: 10px;
   -moz-background-clip: padding;
}

.botcellline {
   border-bottom: 2px #999999 solid;
}

.sortable {
    width:0;
}
</style>
<script>
 function showStatsMsg(domain,log,status) {

    try {
        handleStatsMsg(domain,log,status);
    } catch (e) {

    }
 }
</script>
EOM
    my %conf     = %STAT_CONFIG;
    my $locale   = Cpanel::Locale->get_handle();
    my $now      = time();
    my %stats    = %conf;
    my @defaults = split( /,/, $stats{'DEFAULTGENS'} // '' );
    my @users    = split( /,/, $stats{"VALIDUSERS"}  // '' );
    my %DISABLED;
    my %DEFAULT;

    print "<Br>";

    foreach my $log (@LOGGERS) {
        if ( $Cpanel::CONF{ 'skip' . lc($log) } != 0 )            { $DISABLED{$log} = 1; }
        if ( grep( /^${log}$/i, @defaults ) || $#defaults == -1 ) { $DEFAULT{$log}  = 1; }
    }

    my @PW = Cpanel::PwCache::getpwnam($Cpanel::user);

    my ( $dns, $allowedgens, @ADNS );
    open( CPU, "<", "/var/cpanel/users/$PW[0]" );
    while (<CPU>) {
        chomp();
        if (/^DNS=(\S+)/)      { $dns = $1; }
        if (/^DNS\d+=(\S+)/)   { push( @ADNS, $1 ); }
        if (/^STATGENS=(\S+)/) { $allowedgens = $1; }
        if (/^STATGENS=$/)     { $allowedgens = ''; }
    }
    close(CPU);
    unshift( @ADNS, $dns );

    my (%USERCONF);

    if ( open( my $cf, "<", "$PW[7]/tmp/stats.conf" ) ) {
        while ( readline($cf) ) {
            chomp();
            my ( $stat, $value ) = split( /=/, $_ );
            my ( $gen,  $dom )   = split( /-/, $stat );
            $USERCONF{ lc($dom) }{ lc($gen) } = lc($value);

        }
    }

    my (@userchablegens);
    if ( defined($allowedgens) ) {
        @userchablegens = split( /,/, $allowedgens );
    }
    else {
        @userchablegens = @LOGGERS;
    }

    print qq{<table id="statsmgrtbl" class="sortable table table-striped">};

    my $tdwidth = int( 60 / ( $#LOGGERS + 2 ) ) . "%";
    my $lp_dom  = $locale->maketext('Domain');
    print qq{<thead><tr class="statstblheader"><th width="40%">$lp_dom</th>};
    foreach my $log ( sort @LOGGERS ) {
        $log = lc($log);
        print qq{<th align="center" nonsortable="true" class="nonsortable" width="$tdwidth">${log}</th>};
    }
    print "</tr></thead>";
    print "<tbody>";
    foreach my $dns ( sort @ADNS ) {

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
        print qq{<td wrap align="center">${dnsS}</td>};
        foreach my $log ( sort @LOGGERS ) {
            $log = lc($log);
            if ( $DISABLED{$log} ) {
                print '<td align="center" class="statsenabled"><i class="fas fa-unlock-alt" aria-hidden="true"></i>';
            }
            else {
                if (   ( !grep( /^$PW[0]$/i, @users ) )
                    || ( !grep( /^${log}$/i, @userchablegens ) ) ) {
                    if ( $DEFAULT{$log} ) {
                        print qq{<td align="center" onClick="showStatsMsg('$dnsS','$log','enabled');" class="statsenabled"><i class="fas fa-unlock-alt" aria-hidden="true"></i>};
                    }
                    else {
                        print qq{<td align="center"  onClick="showStatsMsg('$dnsS','$log','disabled');" class="statsdisabled"><i class="fas fa-lock" aria-hidden="true"></i>};
                    }
                }
                else {
                    if ( $USERCONF{$dns}{$log} eq "no" ) {
                        print qq{<td align="center"  onClick="showStatsMsg('$dnsS','$log','disabled');" class="statsdisabled"><i class="fas fa-lock" aria-hidden="true"></i>};
                    }
                    elsif ( $USERCONF{$dns}{$log} eq "yes" ) {
                        print qq{<td align="center"  onClick="showStatsMsg('$dnsS','$log','enabled');" class="statsenabled"><i class="fas fa-unlock-alt" aria-hidden="true"></i>};
                    }
                    else {
                        if ( $DEFAULT{$log} ) {
                            print qq{<td align="center" class="statsenabled"  onClick="showStatsMsg('$dnsS','$log','enabled');"><i class="fas fa-unlock-alt" aria-hidden="true"></i>};
                        }
                        else {
                            print qq{<td align="center" class="statsdisabled"  onClick="showStatsMsg('$dnsS','$log','disabled');"><i class="fas fa-lock" aria-hidden="true"></i>};
                        }
                    }
                }
            }
            print "</td>\n";
        }
        print "</tr>\n";
    }
    print "</tbody>\n";
    print "</table>";

    return 1;
}

=head2 _check_role_and_feature_or_die [PRIVATE]

Checks if the role and feature needed are enabled. Dies when one of the prerequsites is not enabled.

=cut

sub _check_role_and_feature_or_die {
    if ( !Cpanel::Server::Type::Role::WebServer->is_enabled() ) {
        die Cpanel::Exception::create( 'System::RequiredRoleDisabled', [ role => 'WebServer' ] );
    }

    if ( !main::hasfeature('statselect') ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', [ feature_name => 'statselect' ] );
    }
    return;
}

1;
