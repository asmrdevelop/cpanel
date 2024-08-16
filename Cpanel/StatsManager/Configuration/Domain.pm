# cpanel - Cpanel/StatsManager/Configuration/Domain.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::StatsManager::Configuration::Domain;

use cPstrict;

use Cpanel::Autodie   ();
use Cpanel::Exception ();

=head1 MODULE

C<Cpanel::StatManager::Configuration::Domain>

=head1 DESCRIPTION

C<Cpanel::StatManager::Configuration::Domain> provides an OO interface to the
web log analyzer configuration files for a cPanel users domains.

=over

=item /home/<user>/tmp/stats.conf

Each row is a configuration in the format:

  <LOGGER>-<DOMAIN>={yes|no}

=back

=head1 SYNOPSIS

=head2 Retrieve the configuration.

This example show how to setup and run the user configuration helpers.

  use Cpanel::Config::LoadCpConf                  ();
  use Cpanel::Config::LoadCpUserFile::CurrentUser ();
  use Cpanel::StatsManager::Configuration::System ();
  use Cpanel::StatsManager::Configuration::User   ();
  use Cpanel::StatsManager::Configuration::Domain ();

  my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
  my $cpuser = Cpanel::Config::LoadCpUserFile::CurrentUser::load(q/tommy/);

  my $system = Cpanel::StatsManager::Configuration::System->new(
          cpconf => $cpconf,
      );

  my $user = Cpanel::StatsManager::Configuration::User->new(
          cpuser  => $cpuser,
          system  => $system,
      );

  my $config = Cpanel::StatsManager::Configuration::Domain->new(
      cpuser  => $cpuser,
      user    => $user,
      system  => $system,
      homedir => "/home/tommy",
  );

  foreach my $details (@{$config->domain_configuration()}) {
      my @intested_in = qw(tommy.tld);
      next if ! grep { $_ eq $details->{domain} } @intested_in;

      print "Domain: $details->{domain}\n";
      foreach my $analyzer (@{$details->{analyzers}}) {
          print "  Analyzer: $analyzer->{name}\n";
          print "  - Is Enabled on System:       " . ($system->is_analyzer_enabled_on_server($analyzer->{name}) ? "Yes" : "No") . "\n";
          print "  - Default for all users:      " . ($system->is_analyzer_active_by_default($analyzer->{name}) ? "Yes" : "No") . "\n";
          print "  - Available for this user:    " . ($user->is_analyzer_available($analyzer->{name}) ? "Yes" : "No") . "\n";
          print "  - Can be configured by user:  " . ($user->can_user_manage_themself() ? "Yes" : "No") . "\n";
          print "  - Enabled by user for domain: " . ($analyzer->{enabled_by_user} ? "Yes" : "No") . "\n";
          print "  - Enabled:                    " . ($analyzer->{enabled} ? "Yes" : "No") . "\n";
      }
  }

This will produce output similar to the following:

  Domain: tommy.tld
  Analyzer: awstats
  - Is Enabled on System:       Yes
  - Default for all users:      Yes
  - Available for this user:    Yes
  - Can be configured by user:  Yes
  - Enabled by user for domain: No
  - Enabled:                    Yes
  Analyzer: webalizer
  - Is Enabled on System:       Yes
  - Default for all users:      No
  - Available for this user:    Yes
  - Can be configured by user:  Yes
  - Enabled by user for domain: No
  - Enabled:                    No

=head2 Update the configuration.

This example show how to update the web log analyzers configured on each domain.

  use Cpanel::Config::LoadCpConf                  ();
  use Cpanel::Config::LoadCpUserFile::CurrentUser ();
  use Cpanel::StatsManager::Configuration::System ();
  use Cpanel::StatsManager::Configuration::User   ();
  use Cpanel::StatsManager::Configuration::Domain ();

  my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
  my $cpuser = Cpanel::Config::LoadCpUserFile::CurrentUser::load(q/tommy/);

  my $system = Cpanel::StatsManager::Configuration::System->new(
          cpconf => $cpconf,
      );

  my $user = Cpanel::StatsManager::Configuration::User->new(
          cpuser  => $cpuser,
          system  => $system,
      );

  my $config = Cpanel::StatsManager::Configuration::Domain->new(
      cpuser  => $cpuser,
      user    => $user,
      system  => $system,
      homedir => "/home/tommy",
  );

  my @changes = (
    {
      domain => "tommy.tld",
      analyzers => [
            {
                name => "awstats",
                enabled => 1,
            },
            {
                name => "analog",
                enabled => 1,
            },
            {
                name => "webalizer",
                enabled => 1,
            },
            {
                name => "dontknow", # unknown analyzer
                enabled => 1,
            },
        ]
    },
    {
        domain => "wacky.tld",  # unknown domain
        analyzers => [
            {
                name => "awstats",
                enabled => 1,
            },
        ]
    }
  );

  my $issues = $config->save_configuration(@changes);

  if (@{$issues}) {
      print "Issues Found:\n";
      foreach my $issue (@{$issues}) {
          if ($issue->{not_owned}) {
              print " - The domain $issue->{domain} not owned by user.\n";
          }
          elsif( $issue->{not_available} ) {
              print " - The analyzer $issue->{analyzer} not available to user.\n";
          }
          elsif( $issue->{unrecognized} ) {
              print " - The analyzer $issue->{analyzer} not recognized.\n";
          }
      }
  }

  foreach my $details (@{$config->domain_configuration()}) {
      my @changed = qw(tommy.tld wacky.tld);
      next if ! grep { $_ eq $details->{domain} } @changed;
      print "Domain: $details->{domain}\n";
      foreach my $analyzer (@{$details->{analyzers}}) {
          print "  Analyzer: $analyzer->{name}\n";
          print "  - Is Enabled on System:       " . ($system->is_analyzer_enabled_on_server($analyzer->{name}) ? "Yes" : "No") . "\n";
          print "  - Default for all users:      " . ($system->is_analyzer_active_by_default($analyzer->{name}) ? "Yes" : "No") . "\n";
          print "  - Available for this user:    " . ($user->is_analyzer_available($analyzer->{name}) ? "Yes" : "No") . "\n";
          print "  - Can be configured by user:  " . ($user->can_user_manage_themself() ? "Yes" : "No") . "\n";
          print "  - Enabled by user for domain: " . ($analyzer->{enabled_by_user} ? "Yes" : "No") . "\n";
          print "  - Enabled:                    " . ($analyzer->{enabled} ? "Yes" : "No") . "\n";
      }
  }

This will result in the output:

    Issues Found:
    - The analyzer analog not available to user.
    - The analyzer dontknow not recognized.
    - The domain wacky.tld not owned by user.
    Domain: tommy.tld
    Analyzer: awstats
    - Is Enabled on System:       Yes
    - Default for all users:      Yes
    - Available for this user:    Yes
    - Can be configured by user:  Yes
    - Enabled by user for domain: Yes
    - Enabled:                    Yes
    Analyzer: webalizer
    - Is Enabled on System:       Yes
    - Default for all users:      No
    - Available for this user:    Yes
    - Can be configured by user:  Yes
    - Enabled by user for domain: Yes
    - Enabled:                    Yes

=head1 CONSTRUCTOR

=head2 CLASS->new(ARGS)

=head3 ARGUMENTS

=over

=item cpuser - HashRef

The current users configuration.

=item user - Cpanel::StatsManager::Configuration::User

The users configuration for web log analyzers.

=item system - Cpanel::StatsManager::Configuration::System

The system configuration for web log analyzers.

=item homedir - string

Path to the users home directory.

=back

=cut

sub new ( $class, %args ) {
    my $self = {
        cpuser        => $args{cpuser},
        user          => $args{user},
        system        => $args{system},
        homedir       => $args{homedir},
        configuration => [],
        invalidate    => 1,
    };
    bless $self, $class;

    return $self;
}

=head1 PROPERTIES

=head2 INSTANCE->system()

Get the system object.

=cut

sub system ($self) {
    return $self->{system};
}

=head2 INSTANCE->user()

Get the user object.

=cut

sub user ($self) {
    return $self->{user};
}

=head2 INSTANCE->domain_configuration()

Get the collection of domain/logger information.

=head3 RETURNS

Arrayref where each item is a hashref with the following items:

=over

=item domain - string

name of the domain the configuration applies to

=item analyzers - arrayref

list of analyzer configuration for the domain. Each item has the following properties.

=over

=item name - string

Name of the analyzer

=item enabled - Boolean (1|0)

1 if the analyzer is enabled; 0 otherwise. This property represents the overall effect of
the enablement by all possible configuration settings.

=item enabled_by_user - Boolean (1|0)

1 if the analyzer is enabled explicitly by this user on this domain; 0 otherwise.

=back

=back

=cut

sub domain_configuration ($self) {
    if ( $self->{invalidate} ) {
        $self->_load();
        $self->{invalidate} = 0;
    }
    return $self->{configuration};
}

=head1 METHODS

=head2 INSTANCE->_load() [Private]

Loads the data from the /home/<user>/tmp/stats.conf file and builds the domains
configuration model.

=cut

sub _load ($self) {

    my @domains         = $self->_get_user_domains();
    my $can_self_manage = $self->_can_self_manage();
    my $analyzers       = $can_self_manage ? $self->user->analyzers_enabled_by_admin() : $self->system->analyzers_enabled_on_system();

    my %lookup;
    foreach my $domain (@domains) {
        my @analyzers;
        foreach my $analyzer_name ( @{$analyzers} ) {
            my $analyzer_available_on_system = $self->system->is_analyzer_enabled_on_server($analyzer_name);
            my $activated_for_all_users      = $self->system->is_analyzer_active_by_default($analyzer_name);

            my $default_activation;
            if ( !$analyzer_available_on_system ) {
                $default_activation = 0;
            }
            else {
                $default_activation = $activated_for_all_users;
            }

            my $config = {
                name            => lc($analyzer_name),
                enabled         => $default_activation ? 1 : 0,
                enabled_by_user => 0,
            };

            push @analyzers, $config;
            $lookup{$domain}{ lc($analyzer_name) } = $config;
        }

        push @{ $self->{configuration} }, {
            domain    => $domain,
            analyzers => \@analyzers,
        };
    }

    my $home_conf_path = $self->_get_config_path();
    return if !$can_self_manage || !-e $home_conf_path;

    # Configure based on user's ~/tmp/stats.conf
    if ( Cpanel::Autodie::open( my $conf_fh, "<", $home_conf_path ) ) {
        while ( my $line = readline($conf_fh) ) {
            chomp($line);

            # Each line of this log has the following format:
            #
            #   <LOGGER>-<DOMAIN>={yes|no}
            #
            my ( $key,           $value )  = split( /=/, uc($line), 2 );
            my ( $analyzer_name, $domain ) = split( /-/, $key,      2 );

            $analyzer_name = lc($analyzer_name);

            next if !$self->system->is_analyzer_enabled_on_server($analyzer_name);
            $domain = lc($domain);
            $value  = lc($value);
            $value  = $value eq 'yes' ? 1 : 0;

            # Adjust the reference, this updates the reference
            # we put into the $self->{domains} arrayref also.
            $lookup{$domain}{$analyzer_name}{enabled}         = $value;
            $lookup{$domain}{$analyzer_name}{enabled_by_user} = $value;
        }

        Cpanel::Autodie::close($conf_fh);
    }

    return;
}

=head2 INSTANCE->_get_user_domains() [PRIVATE]

Get the list of domain names for the cPanel user.

=cut

sub _get_user_domains ($self) {
    my @domains = sort ( @{ $self->{cpuser}{DOMAINS} } );
    return @domains;
}

=head2 INSTANCE->_get_config_dir() [PRIVATE]

Get the users web log analyzer configuration directory.

=cut

sub _get_config_dir ($self) {
    return $self->{homedir} . "/tmp";
}

=head2 INSTANCE->_get_config_path() [PRIVATE]

Get the users web log analyzer configuration file path.

=cut

sub _get_config_path ($self) {
    return $self->_get_config_dir() . "/stats.conf";
}

=head2 INSTANCE->_can_self_manage() [PRIVATE]

Helper method to check if the user can self manage.

=cut

sub _can_self_manage ($self) {
    return $self->user->can_user_manage_themself();
}

=head2 INSTANCE->save_configuration(@changes)

Save the configuration changes if possible. Any domain/analyzer configs not provided will be disabled automatically.

=head3 ARGUMENTS

=over

=item @changes - Array of domains and analyzers to configure. Each item in the list is a HashRef with the following format.

=over

=item domain - string

Domain name belonging to the cPanel user account.

=item analyzers - ArrayRef

List of analyzers to change for the domain. Each is a HashRef with the following properties:

=over

=item name - string

Name of the analyzer. Must be one of: analog, awstats, or webalizer.

=item enabled - Boolean (1|0)

When 1 you are requesting the analyzer to be enabled for the domain. When 0 you are requesting the analyzer be disabled for the domain.

=back

=back

=back

=head3 RETURNS

ArrayRef with list of issues encountered. Each item is a HashRef with the following properties:

=over

=item domain - string

Name of the domain that had the problem

=item not_owned  - Boolean (1|0)

Optional. When 1, the domain requested is not owned by the cPanel account.

=item analyzer - string

Optional. Name of the analyzer with the problem.

=item not_available - Boolean (1|0)

Optional. When 1, the analyzer requested was either not recognized, was not enabled or is not available for this user.

=back

=cut

sub save_configuration ( $self, @changes ) {

    if ( !$self->_can_self_manage() ) {
        die Cpanel::Exception->create('You may not modify the weblog analyzer configuration. Contact your reseller or hosting provider to make changes to the weblog analyzer selection.');
    }

    my %domains;
    $domains{$_}++ for ( $self->_get_user_domains() );
    require File::Path;
    my $dir = $self->_get_config_dir();
    if ( !-e $dir ) {
        File::Path::make_path( $dir, { 'mode' => 0755, error => \my $errors } );
        if ( $errors && @$errors ) {
            for my $diag (@$errors) {
                my ( $file, $message ) = %$diag;
                if ( $file eq '' ) {
                    die Cpanel::Exception->create_raw($message);
                }
                else {
                    die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $file, error => $message ] );
                }
            }
        }
    }

    # Build the complete list assume everything is off.
    # I would rather have read the config and applied the diff, but
    # this is not how the current app works.
    my %CONFIG;
    foreach my $domain ( keys %domains ) {
        foreach my $analyzer_name ( @{ $self->system->all_analyzers } ) {
            if ( $self->system->is_analyzer_active_by_default($analyzer_name) ) {
                $CONFIG{$domain}->{$analyzer_name} = 1;
            }
            else {
                $CONFIG{$domain}->{$analyzer_name} = 0;
            }
        }
    }

    my @issues;
    foreach my $change (@changes) {
        next
          if !$change->{domain}
          || !$change->{analyzers}
          || ref $change->{analyzers} ne 'ARRAY';

        # Verify we are configuring one of our domains
        if ( !$domains{ $change->{domain} } ) {
            $change->{not_owned} = 1;
            push @issues, {
                domain    => $change->{domain},
                not_owned => 1,
            };
            next;
        }

        foreach my $analyzer ( @{ $change->{analyzers} } ) {
            my $analyzer_name = $analyzer->{name};

            # Skip unrecognized analyzers
            if ( !( grep { $analyzer_name eq $_ } @{ $self->system->all_analyzers } ) ) {
                push @issues, {
                    domain       => $change->{domain},
                    analyzer     => $analyzer_name,
                    unrecognized => 1,
                };
                next;
            }

            # Verify that we can use the analyzer
            if (   !$self->system->is_analyzer_enabled_on_server($analyzer_name)
                || !$self->user->is_analyzer_available($analyzer_name) ) {
                push @issues, {
                    domain        => $change->{domain},
                    analyzer      => $analyzer_name,
                    not_available => 1,
                };
                next;
            }

            # Update the configuration
            $CONFIG{ $change->{domain} }{ $analyzer->{name} } = ( $analyzer->{enabled} == 1 ? 1 : 0 );
        }
    }

    # Each line of this log has the following format:
    #
    #   <LOGGER>-<DOMAIN>={yes|no}
    #
    my $output;
    foreach my $domain ( sort keys %CONFIG ) {
        foreach my $analyzer_name ( sort keys %{ $CONFIG{$domain} } ) {
            $output .= uc($analyzer_name) . "-" . uc($domain) . "=" . format_yes_no( $CONFIG{$domain}{$analyzer_name} ) . "\n";
        }
    }

    my $home_conf_path = $self->_get_config_path();

    require Cpanel::Transaction::File::Raw;
    my $trans = Cpanel::Transaction::File::Raw->new( 'path' => $home_conf_path, 'permissions' => 0644 );
    $trans->set_data( \$output );
    $trans->save_and_close_or_die();

    # Force a reload on next access to the domains() property.
    $self->{invalidate} = 1;

    return \@issues;
}

=head2 format_yes_no(STATE)

Convert the boolean value into a 'yes' or 'no' for the config file.

=head3 ARGUMENTS

=over

=item STATE - number (1|0)

When 1 the answer should be 'yes', when anything else it should be 'no'

=back

=head3 RETURNS

string

=cut

sub format_yes_no ($state) {
    return 'yes' if $state == 1;
    return 'no';
}

1;
