package Cpanel::Koality::Project;

# cpanel - Cpanel/Koality/Project.pm               Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;
use Cpanel::Imports;
extends 'Cpanel::Koality::Base';

use Cpanel::Koality::User ();
use Cpanel::JSON          ();

use constant PROJECT_TYPES => {
    FREE_MONITORING_ONE_SITE => 'unlimited-lite',
};
use constant DEFAULT_PROJECT_TYPE => 'FREE_MONITORING_ONE_SITE';
use constant SYSTEM_TYPES => {
    CUSTOM_PROJECT_TYPE => 'Custom project',
};
use constant DEFAULT_SYSTEM_TYPE => 'CUSTOM_PROJECT_TYPE';

=head1 MODULE

C<Cpanel::Koality::Project>

=head1 DESCRIPTION

C<Cpanel::Koality::Project> is a class that provides methods to create and manage Koality projects.

=head1 ATTRIBUTES

=head2 name - string

The name of the project.

=cut

has 'name' => (
    is => 'rw',
);

=head2 user - C<Cpanel::Koality::User> instance

An instance of C<Cpanel::Koality::User> associated with the current cPanel user.

=cut

has 'user' => (
    is      => 'rw',
    default => sub ($self) { return Cpanel::Koality::User->new( 'cpanel_username' => $self->cpanel_username ) }
);

=head2 url - string

The URL to be monitored by the project.

=cut

has 'url' => (
    is  => 'rw',
    isa => sub {
        require Cpanel::Validate::URL;
        die "Not a valid URL" if !Cpanel::Validate::URL::is_valid_url( $_[0] );
    },
);

=head2 has_alerting - boolean

Whether the project has standard email alerting enabled.

=cut

has 'has_alerting' => (
    is  => 'rw',
    isa => sub {
        die 'Must be a JSON::PP::Boolean object.' if !$_[0]->isa('JSON::PP::Boolean');
    },
    default => sub { return Cpanel::JSON::false }
);

=head2 system_type_id - integer

The ID number of the system type (monitoring template) to be used for the project.

=cut

has 'system_type_id' => (
    is  => 'rw',
    isa => sub {
        require Cpanel::Validate::Integer;
        Cpanel::Validate::Integer::unsigned( $_[0] );
    },
);

=head2 system_size_id - integer

The ID number of the system size (subscription plan) to be used for the project.

=cut

has 'system_size_id' => (
    is  => 'rw',
    isa => sub {
        require Cpanel::Validate::Integer;
        Cpanel::Validate::Integer::unsigned( $_[0] );
    },
);

=head2 owner - integer

The Koality ID number of the user that owns this project.

=cut

has 'owner' => (
    lazy => 1,
    is   => 'rw',
    isa  => sub {
        require Cpanel::Validate::Integer;
        Cpanel::Validate::Integer::unsigned( $_[0] );
    },
    default => sub ($self) { return $self->user->user_id }
);

=head2 check_interval - string

The time interval between website checks.

=cut

has 'check_interval' => (
    is      => 'rw',
    default => "day"
);

=head2 project_identifier - string

An identifier which groups and organizes projects.

=cut

# This will change to something like 'cpanel' in the future.
has 'project_identifier' => (
    is      => 'ro',
    default => '360'
);

=head2 score_metrics - list

The list of standard metrics collected and scored by koality.

=cut

has 'score_metrics' => (
    is      => 'ro',
    default => sub {
        return [
            qw(
              basic-uptime
              basic-performance
              basic-seo
              basic-content
              basic-tech
              basic-security
            )
        ];
    },
);

=head2 location - string

The region in which the monitoring workers are located.

us_east, de, and asia_jp are the only valid locations.

The default value will be a best guess based on the geo location of the domain.

=cut

has 'location' => (
    is      => 'ro',
    lazy    => 1,
    isa     => \&Cpanel::Koality::Validate::valid_geo_location,
    builder => 1
);

sub _build_location ($self) {

    return 'de'      if $self->use_stage;
    return 'us_east' if !$self->url;

    require Cpanel::GeoIPfree;

    my $continent_code = 'NA';

    eval {
        my $geo_url = $self->url =~ s|^https?://||r;
        my $geo     = Cpanel::GeoIPfree->new();
        $geo->Faster();
        my ($country_code) = $geo->LookUp($geo_url);
        $country_code = defined($country_code) ? uc($country_code) : 'US';
        my $map = Cpanel::JSON::LoadFile('/var/cpanel/plugins/koality/country_to_continent_map.json');
        $continent_code = $map->{$country_code} if exists $map->{$country_code};
    };
    if ( my $exception = $@ ) {
        logger->info( "Failed to determine the geo location of " . $self->url . ": $exception" );
    }

    my $koality_locations = {
        'NA' => 'us_east',
        'SA' => 'us_east',
        'EU' => 'de',
        'AF' => 'de',
        'AS' => 'asia_jp',
        'OC' => 'asia_jp',
    };

    return $koality_locations->{$continent_code} // 'us_east';
}

sub _build_api ($self) {

    require Cpanel::Koality::ApiClient;

    if ( !defined $self->user->cluster_endpoint ) {
        my $auth = Cpanel::Koality::Auth->new( cpanel_username => $self->cpanel_username );
        my $user = $auth->auth_session();
        $self->user($user);
    }

    my $api = Cpanel::Koality::ApiClient->new( cpanel_username => $self->cpanel_username );
    $api->auth_token( $self->user->session_token );
    $api->base_url( $self->user->cluster_endpoint );
    return $api;
}

=head1 METHODS

=head2 get_system_types()

Get all system types available to the user.

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

Hashref containing a nested hashref with the available Koality system type names mapped to their IDs.

=over

=item types - hashref

A hashref containing the available system type names as keys and their corresponding ID numbers as values.

=item provider_id - integer

The numerical ID of the backend API provider from which the system types were retrieved.

This changes between staging and production.

=back

=head3 EXAMPLES

my $projects = Cpanel::Koality::Project->new( 'cpanel_username' => $user );

print Dumper $projects->get_all_projects();

=cut

sub get_system_types ($self) {
    $self->api->base_url( $self->user->cluster_endpoint );
    $self->api->method('GET');
    $self->api->endpoint( "project/systems/" . $self->project_identifier . "/systemType" );
    $self->api->payload( { access_token => $self->user->session_token } );
    my $response = $self->api->run();

    my $provider_id = $response->{data}{provider_id};
    my $system_types;

    foreach my $system ( $response->{data}{main_system_types}->@* ) {
        $system_types->{ $system->{name} } = $system->{id};
    }

    return { provider_id => $provider_id, types => $system_types };
}

=head2 get_all_projects()

Get all projects associated with the cPanel user.

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

Hashref containing nested hashrefs with the attributes of Koality projects owned by the user.

=over

=item ID - hashref

An ID number mapped to a nested hashref containing the attributes of the corresponding project.

=over

=item id - integer

The numerical ID of the project.

=item name - string

The name of the project.

=item location - string

The region in which monitoring will take place.

=item systems - hashref

Details about the monitoring systems associated with the project.

=back

=back

=head3 EXAMPLES

my $projects = Cpanel::Koality::Project->new( 'cpanel_username' => $user );

print Dumper $projects->get_all_projects();

=cut

sub get_all_projects ($self) {
    $self->api->method('POST');
    $self->api->endpoint("project/projects/search");
    $self->api->auth_token( $self->user->session_token );
    $self->api->payload( { user => $self->user->user_id, access_token => $self->user->session_token } );

    my $response = $self->api->run();

    my $all_projects_ar = $response->{data}{projects};
    my $all_projects_hr = {};

    foreach my $proj ( $all_projects_ar->@* ) {
        $all_projects_hr->{ $proj->{id} } = $proj;
    }

    return wantarray ? $all_projects_ar->@* : $all_projects_hr;
}

=head2 get_all_scores()

Get all projects associated with the cPanel user.

=head3 ARGUMENTS

=over

=item verbose - boolean - Optional

Whether to output sub-score data (1), or only the master/overall scores (0). Defaults to 1.

=back

=head3 RETURNS

Arrayref containing hashrefs containing both system information, and the associated scores. The return is fully documented in the openapi spec for the related uapi call.

=head3 EXAMPLES

my $projects = Cpanel::Koality::Project->new( 'cpanel_username' => $user );

print Dumper $projects->get_all_scores($verbose);

=cut

sub get_all_scores ( $self, $verbose = 1 ) {
    my $projects = [ $self->get_all_projects() ];

    my @system_ids;
    foreach my $project ( $projects->@* ) {
        push( @system_ids, map { $_->{id} } $project->{systems}->@* );
    }

    my $score_results = [];
    foreach my $system (@system_ids) {
        $self->api->method('POST');
        $self->api->base_url( $self->user->cluster_endpoint );
        $self->api->endpoint("score/scores/$system");
        $self->api->payload( { access_token => $self->user->session_token, scores => $self->score_metrics } );
        my $response = $self->api->run();
        if ( !$verbose ) {
            foreach my $metric ( $self->score_metrics->@* ) {
                $response->{data}{scores}{$metric}{sub_scores} = [];
            }
        }
        push( $score_results->@*, $response->{data} );
    }

    return $score_results;
}

=head2 get_project_by_id( id )

Get information about a specific project by its ID.

=head3 ARGUMENTS

=over

=item id - integer

The project ID number

=back

=head3 RETURNS

Hashref containing nested hashrefs with the attributes of Koality projects owned by the user.

=over

=item id - integer

The numerical ID of the project.

=item name - string

The name of the project.

=item location - string

The region in which monitoring will take place.

=item systems - hashref

Details about the monitoring systems associated with the project.

=back

=head3 EXAMPLES

my $projects = Cpanel::Koality::Project->new( 'cpanel_username' => $user );

print Dumper $projects->get_project_by_id( $project_id );

=cut

sub get_project_by_id ( $self, $id ) {
    my $all_projs = $self->get_all_projects();
    return $all_projs->{$id} || die "No project with id $id exists.";
}

=head2 get_system_id_for_type()

Get system ID number given a system type.

=head3 ARGUMENTS

=over

=item type - string

The name of the system type in question.

=back

=head3 RETURNS

The ID number of the system type.


=head3 EXAMPLES

my $projects = Cpanel::Koality::Project->new( 'cpanel_username' => $user );

print Dumper $projects->get_system_id_for_type( $system_type );

=cut

sub get_system_id_for_type ( $self, $type ) {

    my $system_types = $self->get_system_types();
    return $system_types->{types}{$type} || die "The system type $type does not exist.";
}

=head2 get_system_size_id( type )

Get system size ID number given a system size type. This is essentially a subscription plan.

=head3 ARGUMENTS

=over

=item type - string

The system size type to retrieve the ID for.

=back

=head3 RETURNS

The ID number of the system size type in question.

=head3 EXAMPLES

my $projects = Cpanel::Koality::Project->new( 'cpanel_username' => $user );

print Dumper $projects->get_system_size_id( $system_size );

=cut

sub get_system_size_id ( $self, $type ) {

    my $subscription = $self->user->get_subscription();
    return $subscription->{systems_new}{$type}{id} || die "The system size $type does not exist.";

}

=head2 create_project( { name => ... } )

=head3 ARGUMENTS

=over

=item name - string - Required

The name of the project to create.

=item url - string - Required

The url to monitor.

=item has_alerting - boolean

Whether to enable standard email alerting.

=item system_type - string

The type of monitoring system template to use for the project. Defaults to "Custom project"

=back

=head3 RETURNS

Hashref that contains the users current projects.

=over

=item id - integer

The project ID number.

=item identifier - integer

The project identifier.

=item location - string

The region the project will be monitored from.

=item name - string

The project's name.

=item role - hashref

Information about the user that owns the project.

=over

=item id - integer

Role ID number.

=item name - string

Role name.

=back

=item systems - arrayref

An arrayref containing hashrefs describing the monitoring systems.

=over

=item name - string

The name of the system.

=item id - integer

The ID number of the system.

=item description - string

A description of the system.

=item domain - string

The base system URL.

=item interval - string

The time interval between system checks.

=item limits - hashref

A hashref containing restrictions to be placed on the monitoring system.

=over

=item maximumCrawlDepth - integer

Maximum crawl depth.

=back

=item system_type - hashref

Hashref containing information about the monitoring template that is in use for the system.

=over

=item name - string

Name of the system type.

=item id - integer

ID of the system type.

=item fixedComponents - boolean

Whether the system components are immutable.

=back

=back

=back

=head3 EXAMPLES

my $projects = Cpanel::Koality::Project->new( 'cpanel_username' => $user );
print Dumper $proj->create_project( { name => $project_name, url => $project_url } );

=cut

sub create_project ( $self, $args ) {

    $self->name( $args->{name} // die 'Must define a project name.' );
    $self->url( $args->{url}   // die 'Must define a url to monitor.' );
    $self->has_alerting( $args->{has_alerting} ? Cpanel::JSON::true() : Cpanel::JSON::false() );

    my $system_type = $args->{system_type} // SYSTEM_TYPES()->{ DEFAULT_SYSTEM_TYPE() };
    $self->system_type_id( $self->get_system_id_for_type($system_type) );

    $self->system_size_id( $self->get_system_size_id( PROJECT_TYPES()->{ DEFAULT_PROJECT_TYPE() } ) );

    $self->api->method('POST');
    $self->api->endpoint("project/systems/system");
    $self->api->payload(
        {
            name                  => $self->name,
            base_url              => $self->url,
            owner                 => $self->owner,
            system_type           => $self->system_type_id,
            add_standard_alerting => $self->has_alerting,
            system_size           => $self->system_size_id,
            location              => $self->location,
            check_interval        => $self->check_interval,
            access_token          => $self->user->session_token
        }
    );

    my $response = $self->api->run();
    return $self->get_project_by_id( $response->{data}{project}{id} );
}

=head2 create_component( $args )

Get system size ID number given a system size type. This is essentially a subscription plan.

=head3 ARGUMENTS

=over

=item projectid - string - Required

The ID of the project to attach this component to.

=item systemid - string - Required

The ID of the system to attach this component to.

=item domain - string - Required

The URL that the component will monitor.

=back

=head3 RETURNS

Hashref of the details of the newly created component.

=over

=item status - string

The status message of the API call, can be success or failure.

=item message - string

The message returned by the API call.

=item data - Hashref

The details of the created component.

=over

=item check_enabled - boolean

Signals if this component enabled.

=item component - Hashref

The details of the created component.

=item name - string

The name of the component.

=item device - Hashref

The details of the user agent.

=item url - string

The URL that is being monitored.

=item system_type - Hashref

Details of the system type used for this component.

=item id - string

The ID of the newly created component.

=back

=back

=head3 EXAMPLES

my $proj = Cpanel::Koality::Project->new();

print Dumper $proj->create_component({ projectid => '1901', systemid => '2787', domain => 'https://koality.io/ok'});

=cut

sub create_component ( $self, $args ) {

    my $projectid = $args->{projectid} // die 'Must define a projectid for the component to attach.';
    my $systemid  = $args->{systemid}  // die 'Must define a systemid for the component to attach.';
    my $domain    = $args->{domain}    // die 'Must define a domain.';
    my $name      = $args->{name}      // 'Homepage';

    my $component_types = $self->get_component_types($projectid);

    # currently only 'html' and 'sitemap' exists
    # 'html' seem to be the best choice for most of our cases.
    my $component_type_id = $component_types->{html}{id};

    $self->api->method('POST');
    $self->api->endpoint('project/components');
    $self->api->payload(
        {
            access_token        => $self->user->session_token,
            system              => $systemid,
            url                 => $domain,
            name                => $name,
            device_id           => 1,
            system_type_id      => $component_type_id,
            enableToolsBySystem => Cpanel::JSON::true(),
        }
    );

    return $self->api->run();
}

=head2 get_component_types( $projectid )

Get all possible component types for the given project.

=head3 ARGUMENTS

=over

=item projectid - string

The project ID to get component types for.

=back

=head3 RETURNS

A hashref of the possible component types. These vary based on the Koality backend used.

=head3 EXAMPLES

my $projects = Cpanel::Koality::Project->new( 'cpanel_username' => $user );

print Dumper $projects->get_component_types( '1234' );

=cut

sub get_component_types ( $self, $projectid ) {
    $self->api->method('GET');
    $self->api->endpoint("project/components/componenttypes/$projectid");
    $self->api->payload( { access_token => $self->user->session_token } );
    my $response = $self->api->run();

    my $system_types = {};
    foreach my $type ( $response->{data}{system_types}->@* ) {
        $system_types->{ $type->{identifier} } = $type;
    }

    return $system_types;
}

1;
