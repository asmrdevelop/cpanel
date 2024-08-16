# cpanel - Cpanel/StatsManager/Configuration/System.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::StatsManager::Configuration::System;

use cPstrict;

use Cpanel::Autodie              ();
use Cpanel::StatsManager::Consts ();

use constant CONFIG_PATH => '/etc/stats.conf';

=head1 MODULE

C<Cpanel::StatManager::Configuration>

=head1 DESCRIPTION

C<Cpanel::StatManager::Configuration::System> provides an OO interface to the
various system settings controlling web log analyzer access.

=over

=item /etc/stats.conf - The file contains the global setting for the web log analyzers configured on the server including:

=over

=item DEFAULTGENS - CSV

A comma separated list of the web log analyzers installed on the system. Note: The names a all upper-case letters.

=item VALIDUSERS - CSV

A comma separated list of the cPanel users that can manage their own web log analyzer configuration.

=item ALLOWALL - Boolean (yes|no)

When `yes`, all users can configure their own web log analyzers. When missing or 'no', only users in the VALIDUSERS list can configure their own web log analyzers.

=back

=item /var/cpanel/cpanel.config - This file contains which web log analyzers are enabled in the following properties:

=over

=item skipanalog - boolean

When 1, analog is not available on the system. When missing or 0, analog is available.

=item skipawstats - boolean

When 1, awstats is not available on the system. When missing or 0, awstats is available.

=item skipwebalizer - boolean

When 1, webalizer is not available on the system. When missing or 0, webalizer is available.

=back

=back

=head1 SYNOPSIS

This example runs you through how to initialize the object and
how to use the properties and helper methods.

  use Cpanel::StatsManager::Configuration::System ();
  use Cpanel::Config::LoadCpConf                  ();

  my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

  my $config = Cpanel::StatsManager::Configuration::System->new(
    cpconf  => $cpconf,
  );

  print "All Self Manage: " . ($config->all_uses_can_manage_themselves() ? "yes" : "no") . "\n";
  print "User \"tommy\" Self Manage: " . ($config->can_user_manage_themself("tommy") ? "yes" : "no") . "\n";
  print "Users that can Self Manage:\n";
  foreach my $user (@{$config->users_that_can_manage_themselves()}) {
      print - "$user\n";
  };
  print "\n";

  print "All Analyzers\n";
  foreach my $analyzer (@{$config->all_analyzers()}) {
      print "- $analyzer is: " . ($config->is_analyzer_enabled_on_server($analyzer) ? "Enabled" : "Disabled") . "\n";
      print "- $analyzer is: " . ($config->is_analyzer_active_by_default($analyzer) ? "Actived" : "Deactivate") . " by default.\n";
  }
  print "\n";

  print "Enabled Analyzers\n";
  foreach my $analyzer (@{$config->analyzers_enabled_on_system()}) {
      print "- $analyzer is: " . ($config->is_analyzer_enabled_on_server($analyzer) ? "Enabled" : "Disabled") . "\n";
      print "- $analyzer is: " . ($config->is_analyzer_active_by_default($analyzer) ? "Actived" : "Deactivate") . " by default.\n";
  }
  print "\n";

  print "Analyzers on by Default\n";
  foreach my $analyzer (@{$config->analyzers_enabled_by_default()}) {
      print "- $analyzer is: " . ($config->is_analyzer_enabled_on_server($analyzer) ? "Enabled" : "Disabled") . "\n";
      print "- $analyzer is: " . ($config->is_analyzer_active_by_default($analyzer) ? "Actived" : "Deactivate") . " by default.\n";
  }
  print "\n";

You should get output similar to the following:

    All Self Manage: no
    User "tommy" Self Manage: yes
    Users that can Self Manage:
    -tommy
    -alternate

    All Analyzers
    - analog is: Disabled
    - awstats is: Enabled
    - webalizer is: Disabled

    Just Enabled Analyzers
    - awstats is: Enabled

=head1 CONSTRUCTOR

=head2 CLASS->new(ARGS)

=head3 ARGUMENTS

=over

=item cpconf - Reference to the Cpanel config object.

=back

=cut

sub new ( $class, %args ) {

    my $self = {
        cpconf                                => $args{cpconf},
        enabled                               => {},
        _allow_all_users_to_manage_themselves => 0,
        _analyzers_enabled_by_default         => [],
        _users                                => [],
    };
    bless $self, $class;

    $self->_load_stats_conf();
    $self->_load_cpanel_conf();

    return $self;
}

=head1 PROPERTIES

=head2 INSTANCE->all_uses_can_manage_themselves()

1 when all users can manage their own configuration, 0 otherwise.

=cut

sub all_uses_can_manage_themselves ($self) {
    return $self->{_allow_all_users_to_manage_themselves};
}

=head2 INSTANCE->all_analyzers()

Arrayref of analyzers that are can be used on the system.

=cut

sub all_analyzers ($self) {
    return \@Cpanel::StatsManager::Consts::ALL_ANALYZERS;
}

=head2 INSTANCE->analyzers_enabled_on_system()

Arrayref of analyzers that are enabled on the system.

=cut

sub analyzers_enabled_on_system ($self) {
    return $self->{_enabled_on_server};
}

=head2 INSTANCE->analyzers_enabled_by_default()

Arrayref of analyzers that are enabled by default for
all users domains.

=cut

sub analyzers_enabled_by_default ($self) {
    return $self->{_analyzers_enabled_by_default};
}

=head2 INSTANCE->users_that_can_manage_themselves()

Arrayref of usernames that area allowed to manage their own web log analyzer configurations.

=cut

sub users_that_can_manage_themselves ($self) {
    return $self->{_users};
}

=head1 METHODS

=head2 INSTANCE->can_user_manage_themself(USER)

Check if the C<USER> can manage their own web log analyzer configuration.

=head3 ARGUMENTS

=over

=item USER - string

The cPanel username to check.

=back

=head3 RETURNS

1 when the user can manage their own configuration; 0 otherwise.

=cut

sub can_user_manage_themself ( $self, $user ) {
    return 1 if $self->{_allow_all_users_to_manage_themselves};
    return 1 if grep { $user eq $_ } @{ $self->{_users} };
    return 0;
}

=head2 INSTANCE->is_analyzer_enabled_on_server(ANALYZER)

Check if the C<ANALYZER> is enabled on the server.

=head3 ARGUMENTS

=over

=item ANALYZER - string

The analyzer you want to check.

=back

=head3 RETURNS

1 when the user can manage their own configuration; 0 otherwise.

=cut

sub is_analyzer_enabled_on_server ( $self, $analyzer ) {
    return ( grep { lc($analyzer) eq lc($_) } @{ $self->{_enabled_on_server} } ) ? 1 : 0;
}

=head2 INSTANCE->is_analyzer_active_by_default(ANALYZER)

Check if the C<ANALYZER> is turned on by default for all users.

=head3 ARGUMENTS

=over

=item ANALYZER - string

The analyzer you want to check.

=back

=head3 RETURNS

1 when the analyzer is enabled by default;
0 when either the analyzer is disabled on the server or disabled by default.

=cut

sub is_analyzer_active_by_default ( $self, $analyzer ) {
    return 0 if !$self->is_analyzer_enabled_on_server($analyzer);
    return ( grep { lc($analyzer) eq lc($_) } @{ $self->{_analyzers_enabled_by_default} } ) ? 1 : 0;
}

=head3 INSTANCE->_load_stats_conf() [Private]

Load the data from '/etc/stats.conf'

=cut

sub _load_stats_conf ($self) {
    return if ( !-e CONFIG_PATH );

    my %config;
    Cpanel::Autodie::open( my $statsconf_fh, '<', CONFIG_PATH );
    my ( $var, $val );
    while ( my $line = readline $statsconf_fh ) {
        chomp $line;
        ( $var, $val ) = split( /=/, $line );
        next if ( !defined $var || $var eq '' || !defined $val || $val eq '' );
        $config{ uc($var) } = $val;
    }
    Cpanel::Autodie::close $statsconf_fh;

    if ( defined( $config{DEFAULTGENS} ) ) {
        my $default_analyzers_csv = $config{DEFAULTGENS};
        $self->{_analyzers_enabled_by_default} = [ map { lc($_) } csv_to_array($default_analyzers_csv) ];
    }
    else {
        $self->{_analyzers_enabled_by_default} = [@Cpanel::StatsManager::Consts::ALL_ANALYZERS];
    }

    if ( defined( $config{VALIDUSERS} ) ) {
        my $users_csv = $config{VALIDUSERS};
        $self->{_users} = [ csv_to_array($users_csv) ];
    }
    else {
        $self->{_users} = [];
    }

    if ( defined( $config{ALLOWALL} ) ) {
        $self->{_allow_all_users_to_manage_themselves} = $config{ALLOWALL} eq 'yes' ? 1 : 0;
    }
    else {
        $self->{_allow_all_users_to_manage_themselves} = 0;
    }

    return;
}

=head3 INSTANCE->_load_cpanel_conf() [Private]

Load the data from '/var/cpanel/cpanel.config'

=cut

sub _load_cpanel_conf ($self) {
    my @enabled_on_server;
    foreach my $analyzer_name ( @{ $self->all_analyzers() } ) {
        if ( $self->{cpconf}{ 'skip' . $analyzer_name } == 0 ) {
            push @enabled_on_server, $analyzer_name;
        }
    }
    $self->{_enabled_on_server} = \@enabled_on_server;
    return;
}

=head3 csv_to_array() [STATIC]

Convert a string with comma delimited data into an ArrayRef of the items.

=cut

sub csv_to_array ($csv) {
    return split( /,/, $csv );
}

1;
