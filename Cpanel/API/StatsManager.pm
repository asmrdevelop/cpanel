# cpanel - Cpane/API/StatsManager                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::StatsManager;

use cPstrict;

use Cpanel::StatManager ();
use Cpanel::Imports;

=encoding utf-8

=head1 MODULE

C<Cpanel::API::StatsManager>

=head1 DESCRIPTION

C<Cpanel::API::StatsManager> provides tools for listing and changing which web log analyzers are used for each domain belonging to a cPanel account.

=head1 SYNOPSIS

=head2 Retrieve the current configuration

  use Cpanel::API::StatsManager ();
  use Cpanel::Args              ();
  use Cpanel::Result            ();

  my $args   = Cpanel::Args->new();
  my $result = Cpanel::Result->new();
  my $ok = Cpane::API::StatsManager::get_configuration($args, $result);
  if ($ok) {
      require Data::Dumper;
      print Data::Dumper($result->data());
  }

=head2 Enable C<webalizer> on the domain C<domain.com>

  $args = Cpanel::Args->new({
      changes => [
          {
            domain => "domain.com",
            analyzers => [
                {
                    name => "webalizer",
                    enabled => 1,
                }
            ]
        }
    ]);
  $result = Cpanel::Result->new();
  $ok = Cpane::API::StatsManager::save_configuration($args, $result);
  if ($ok) {
      require Data::Dumper;
      print Data::Dumper($result->data());
  }

=head1 FUNCTIONS

=head2 get_configuration()

This function lists the configuration of the web log anayzers for each domain on the cPanel account.

=head3 RETURNS

=head4 data

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

=head4 metadata

=over

=item locked -  Boolean (1|0)

When 1, the analyzer cannot be managed by the cPanel user; When 0, the analyzer can be managed by the cPanel user.

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

=back

=head3 THROWS

=over

=item When the WebServer role is not enabled on the server.

=item When one of the configuration files cannot be read due to an error.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty StatsManager get_configuration

The returned data will contain a structure similar to the JSON below:

    ...
    "data" : [
        {
            "domain": "domain.com",
            "analyzers": [
                {
                    "name": "analog",
                    "enabled": 0,
                    "enabled_by_user": 0,
                },
                {
                    "name": "awstats",
                    "enabled": 1,
                    "enabled_by_user": 1,
                },
            ]
        }
    ],
    "metadata": {
        "locked": 0,
        "analyzers": [
            {
                "name": "analog",
                "enabled_by_default": 0,
                "available_for_user": 1
            },
            {
                "name": "awstats",
                "enabled_by_default": 1,
                "available_for_user": 1
            },
        ],
        ...
    }
    ...

=head4 Template Toolkit

    [%
    SET result = execute('StatsManager', 'get_configuration', {

    });
    IF result.status;
        IF result.metadata.locked %]
            The current user cannot edit this configuration.
        [% ELSE %]
            The current user can edit this configuration.
       [%
       END;
       FOREACH item IN result.data %]
         Domain: [% item.domain %]
         [% FOREACH analyzer IN item.analyzers %]
            [% analyzer.name -%] -
            [%- IF !result.metadata.locked -%]
                [%- IF analyzer.enabled -%]
                    Enabled
                [% ELSE %]
                    Disabled
                [% END %]
                [% IF analyzer.enabled_by_user %]
                    [ By me ]
                [% ELSE %]
                    [ By my admin ]
                [% END %]
            [%- ELSE -%]
                [%- IF analyzer.enabled -%]
                    Enabled [By my admin]
                [%- ELSE -%]
                    Disabled [By my admin]
                [%- END -%]
            [%- END %]
         [% END %]
       [%
       END;
    END %]

=cut

sub get_configuration ( $args, $result ) {
    my $config = Cpanel::StatManager::get_configuration();
    $result->data( $config->{domains} );
    $result->metadata( 'analyzers', $config->{analyzers} );
    $result->metadata( 'locked',    $config->{locked} );
    return 1;
}

=head2 save_configuration()

This function saves the users choice about which web log anayzers are enabled for each domain on their cPanel users account.
If the log anayzers are controlled by the reseller or root account, the user cannot manage which log analyzers are enabled or disabled.

This UAPI call must be called using JSON semantics:

=over

=item You must set the content type to:  `Content-Type: 'application/json'`.

=item You must call this with UAPI function with an HTTP POST request.

=back

=head3 ARGUMENTS

=over

=item changes - ArrayRef

List of domains and their web log analyzer configurations.

Each element contains the following hashref:

=over

=item domain - string

The domain you want to apply the configuration to.

=item analyzers - ArrayRef

List of the analyzers you want to configure. Each analyzer is an hashref with the following structure.

=over

=item name - string

Name of the analyzer. Must be one of: analog, awstats, webalizer.

=item enabled - Boolean (0|1)

When 1, enabled the named analyzer.

When 0, disable the named analyzer.

=back

=back

=back

=head3 RETURNS

=head4 data

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

=head4 metadata

=over

=item locked -  Boolean (1|0)

When 1, the analyzer cannot be managed by the cPanel user; When 0, the analyzer can be managed by the cPanel user.

=item analyzers - ArrayRef

List of system level analyzer configuration where each item is a HashRef and has the following properties:

=over

=item enabled_by_default -  Boolean (1|0)

When 1, the analyzer is enabled for all user by default; When 0, the analyzer is not enabled for all user by default.

=item available_for_user -  Boolean (1|0)

When 1, the analyzer is enabled for use by the current user; When 0, the analyzer is not available to the current user.

=back

=back

=head3 THROWS

=over

=item When you do not provide the configuration input.

=item When the system and/or user stats configuration files are not writable by the system.

=item When the system restricts the user from making changes to configuration.

=item When the provided parameter data for 'changes' is not an ARRAY.

=back

=head3 EXAMPLES

=head4 Command line usage

    echo '{
    "changes": [
        {
            "domain": "domain.com",
            "analyzers": [
                { "name": "awstats",   "enabled": 0 },
                { "name": "webalizer", "enabled": 1 },
                { "name": "unknown",   "enabled": 1 },
                { "name": "analog",    "enabled": 1 }
            ]
        },
        {
            "domain": "unknown.com",
            "analyzers": [
                { "name": "awstats",   "enabled": 1 }
            ]
        }
    ]
}' | bin/uapi --user=cpuser --input=json --output=jsonpretty StatsManager save_configuration

The returned data will contain a structure similar to the JSON below:

 {
   "func" : "save_configuration",
   "apiversion" : 3,
   "result" : {
      "metadata" : {
         "transformed" : 1,
         "locked" : 0,
         "analyzers" : [
            {
               "available_for_user" : 1,
               "enabled_by_default" : 1,
               "name" : "awstats"
            },
            {
               "name" : "webalizer",
               "available_for_user" : 1,
               "enabled_by_default" : 0
            }
         ]
      },
      "data" : [
         {
            "analyzers" : [
               {
                  "enabled_by_user" : 0,
                  "name" : "awstats",
                  "enabled" : 0
               },
               {
                  "enabled" : 1,
                  "name" : "webalizer",
                  "enabled_by_user" : 1
               }
            ],
            "domain" : "domain.com"
         }
    ],
    "messages" : null,
    "warnings" : [
         "When attempting to configure the “domain.com” domain, the analyzer “unknown” was not recognized.",
         "When attempting to configure the “domain.com” domain, the analyzer “analog” was not available.",
         "You do not own the “unknown.com” domain"
    ],
    "errors" : null,
    "status" : 1
   },
   "module" : "StatsManager"
 }

=head4 Template Toolkit

Enable awstats and analog and disable webalizer for a domain you own.

    [%
    SET result = execute('StatsManager', 'save_configuration', {
        changes => [
            domain => 'domain.com',
            analyzers => [
                {
                    name => awstats,
                    value => 1,
                },
                {
                    name => analog,
                    value => 1,
                },
                {
                    name => webalizer,
                    value => 0,
                },
            ]
        ]
    });
    IF result.status %]
        Updated Configuration:

        [% FOREACH config IN result.data %]
            Domain: [% config.domain %]
            Editable: [% result.metadata.locked ? "No" : "Yes" %]
            [% FOREACH analyzer IN result.data.0.analyzers %]
                [% analyzer.name %]:
                [%- IF analyzer.enabled -%]
                    Enabled
                [%- ELSIF !analyzer.enabled -%]
                    Disabled
                [%- END; -%]
            [% END %]
    [% END %]

=cut

sub save_configuration ( $args, $result ) {
    my $changes = $args->get_required('changes');
    my $config  = Cpanel::StatManager::save_configuration($changes);

    $result->data( $config->{domains} );
    $result->metadata( 'analyzers', $config->{analyzers} );
    $result->metadata( 'locked',    $config->{locked} );
    foreach my $issue ( @{ $config->{issues} } ) {
        my $warning = '';
        if ( $issue->{not_owned} ) {
            $warning = locale()->maketext( 'You do not own the “[_1]” domain.', $issue->{domain} );
        }
        elsif ( $issue->{not_available} ) {
            $warning = locale()->maketext( 'When attempting to configure the “[_1]” domain, the analyzer “[_2]” was not available.', $issue->{domain}, $issue->{analyzer} );
        }
        elsif ( $issue->{unrecognized} ) {
            $warning = locale()->maketext( 'When attempting to configure the “[_1]” domain, the analyzer “[_2]” was not recognized.', $issue->{domain}, $issue->{analyzer} );
        }
        if ($warning) {
            $result->raw_warning($warning);
        }
    }
    return 1;
}

our %API = (
    _needs_role       => 'WebServer',
    _needs_feature    => 'statselect',
    get_configuration => {
        allow_demo => 1,
    },
    save_configuration => {
        requires_json => 1,
    },
);

1;
