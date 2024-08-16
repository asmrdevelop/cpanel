# cpanel - Cpanel/StatsManager/Configuration/User.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::StatsManager::Configuration::User;

use cPstrict;

use Cpanel::StatsManager::Consts ();

=head1 MODULE

C<Cpanel::StatsManager::Configuration::User>

=head1 DESCRIPTION

C<Cpanel::StatsManager::Configuration::User> provides an OO interface to the
various web log analyzer configuration files for a cPanel user.

=over

=item /var/cpanel/users/<user> - The  file contains the user specific setting for the web log analyzers.

=over

=item STATGENS - csv

Comma separated list of web log analyzers configured for this user.

=back

=back

=head1 SYNOPSIS

This example show how to setup and run the user configuration helpers.

  use Cpanel::Config::LoadCpConf                  ();
  use Cpanel::Config::LoadCpUserFile::CurrentUser ();
  use Cpanel::StatsManager::Configuration::System ();
  use Cpanel::StatsManager::Configuration::User   ();

  my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
  my $cpuser = Cpanel::Config::LoadCpUserFile::CurrentUser::load(q/tommy/);

  my $system = Cpanel::StatsManager::Configuration::System->new(
          cpconf => $cpconf,
      );

  my $user = Cpanel::StatsManager::Configuration::User->new(
      cpuser  => $cpuser,
      system  => $system,
  );

  foreach my $analyzer (@{$user->analyzers_enabled_by_admin()}) {
      print "$analyzer:\n";
      print "- Enabled on server:                  " . ($system->is_analyzer_enabled_on_server($analyzer) ? "Yes" : "No") . "\n";
      print "- Activated by default for all users: " . ($system->is_analyzer_active_by_default($analyzer) ? "Yes" : "No") . "\n";
      print "- Available for this user:            " . ($user->is_analyzer_available($analyzer) ? "Yes" : "No") . "\n";
      print "- Can be configured by this user:     " . ($user->can_user_manage_themself() ? "Yes" : "No") . "\n";
  }

You should get output similar to the following:

    analog:
    Can be used: No
    Can be configured by "tommy": No
    awstats:
    Can be used: Yes
    Can be configured by "tommy": Yes
    webalizer:
    Can be used: Yes
    Can be configured by "tommy": Yes

=head1 CONSTRUCTOR

=head2 CLASS->new(ARGS)

=head3 ARGUMENTS

=over

=item cpuser - Reference to loaded cPanel user configuration file.

=item system - Cpanel::StatsManager::Configuration::System

Loaded system configuration for web log analyzers on the system.

=back

=cut

sub new ( $class, %args ) {
    my $self = {
        cpuser                          => $args{cpuser},
        system                          => $args{system},
        _enabled_for_this_users_domains => [],
    };
    bless $self, $class;

    $self->_load_user_config();

    return $self;
}

=head1 PROPERTIES

=head2 INSTANCE->system()

Get the system object.

=cut

sub system ($self) {
    return $self->{system};
}

=head1 METHODS

=head2 INSTANCE->analyzers_enabled_by_admin()

Get a list of the weblog analyzers that have been turned on for this users domains.

=head3 RETURNS

Arrayref of string - list of the web log analyzers enabled for the user by the admin.
These analyzers are on for all domains.

=cut

sub analyzers_enabled_by_admin ($self) {
    return $self->{_enabled_for_this_users_domains};
}

=head2 INSTANCE->is_analyzer_available(ANALYZER)

Check if the C<ANALYZER> can be managed by the user.

=head3 ARGUMENTS

=over

=item ANALYZER - string

The analyzer you want to check.

=back

=head3 RETURNS

1 when the analyzer can be managed by the user.
0 when either the analyzer is disabled on the server or disabled for the user by the admin.

=cut

sub is_analyzer_available ( $self, $analyzer ) {
    return ( grep { lc($analyzer) eq $_ } @{ $self->{_enabled_for_this_users_domains} } ) ? 1 : 0;
}

=head2 INSTANCE->can_user_manage_themself()

Check if the current user can manager their own web log configuration.

=head3 RETURNS

1 when the user can manage their own configuration; 0 otherwise.

=cut

sub can_user_manage_themself ($self) {
    my $username = $self->{cpuser}{USER};
    return $self->system->can_user_manage_themself($username);
}

=head2 INSTANCE->_load_user_config() [Private]

Load the configuration from the user and system.

=cut

sub _load_user_config ($self) {

    # Start with all of them?
    my @enabled_for_this_users_domains = @Cpanel::StatsManager::Consts::ALL_ANALYZERS;

    # Lookup what loggers have been enabled
    # for all the domains on a user by the admin.
    if ( exists $self->{cpuser}{STATGENS}
        && defined $self->{cpuser}{STATGENS} ) {
        @enabled_for_this_users_domains = map { lc($_) } split( /,/, $self->{cpuser}{STATGENS} );
    }

    # Filter out the ones that are disabled globally
    @enabled_for_this_users_domains = grep { $self->system->is_analyzer_enabled_on_server($_) } @enabled_for_this_users_domains;

    $self->{_enabled_for_this_users_domains} = \@enabled_for_this_users_domains;

    return;
}

1;
