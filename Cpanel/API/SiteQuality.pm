package Cpanel::API::SiteQuality;

# cpanel - Cpanel/API/SiteQuality.pm               Copyright 2024 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Imports;

use Cpanel::Koality::Auth     ();
use Cpanel::Koality::User     ();
use Cpanel::Koality::Project  ();
use Cpanel::Validate::Boolean ();

our %API = (
    create_site_quality_user     => { allow_demo => 0 },
    delete_site_quality_user     => { allow_demo => 0 },
    is_site_quality_user_enabled => { allow_demo => 0 },
    get_app_token                => { allow_demo => 0 },
    create_project               => { allow_demo => 0 },
    get_all_scores               => { allow_demo => 0 },
    has_site_quality_user        => { allow_demo => 0 },
    send_activation_email        => { allow_demo => 0 },
    reset_config                 => { allow_demo => 0 },
    verify_code                  => { allow_demo => 0 },
    get_environment              => { allow_demo => 0 },
);

=head1 MODULE

C<Cpanel::API::SiteQuality>

=head1 DESCRIPTION

C<Cpanel::API::SiteQuality> provides methods to create and manage Site Quality Monitoring users.

=head1 FUNCTIONS

=head2 create_site_quality_user(email => ...)

=head3 ARGUMENTS

=over

=item email - string - Required

The email to use for the new Site Quality Monitoring account.

=item password - string - Optional

The password of the new Site Quality Monitoring account.

If no password is given, one is auto-generated.

This value is not saved on the system.

=back

=head3 RETURNS

Hashref of the Site Quality Monitoring user attributes.

=over

=item app_token - string

The long lived token for this account.

This token is required to authenticate with Site Quality Monitoring servers.

If this token is lost, the user must create a new account.

=item enabled - boolean

Whether or not the account has been enabled.

=item username - string

The user name of the new Site Quality Monitoring account.

=back

=head3 EXAMPLES

CLI ( Arguments must be uri escaped ):

uapi --user=cpanel_user SiteQuality create_site_quality_user email=email_address%40hostname.com

TT:

 [%
     SET result = execute('SiteQuality', 'create_site_quality_user', { email => 'email_address@hostname.com' });
     SET token = result.data.app_token;
 %]

=cut

sub create_site_quality_user ( $args, $result ) {

    my $email = $args->get_length_required('email');
    my $pass  = $args->get('password');

    my $auth = Cpanel::Koality::Auth->new();
    my $user = eval { $auth->create_user( $email, $pass ) };
    if ( my $exception = $@ ) {
        if ( defined Scalar::Util::blessed($exception) && Scalar::Util::blessed($exception) eq 'Cpanel::Exception::HTTP::Server' ) {
            my $content = Cpanel::JSON::Load( $exception->get('content') );
            if ($content) {
                $content = $content->{'error'};
            }
            if ( !$content ) {
                $content = $exception->get('reason') || locale->maketext('Unknown failure.');
            }
            die locale->maketext( 'Failed to create the user [_1]: [_2]', $email, $content ) . "\n";
        }
        die $exception;
    }

    $result->data(
        {
            app_token => $user->app_token,
            username  => $user->koality_username,
            enabled   => $user->enabled
        }
    );

    return 1;
}

=head2 delete_site_quality_user()

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

The result status of the requested deletion.

=over

=item deleted - bool

True - user has been successfully deleted.

False - there has been an error and the user was not successfully deleted.

=back

=head3 EXAMPLES

CLI:

uapi --user=cpanel_user SiteQuality delete_site_quality_user

TT:

 [%
     SET result = execute('SiteQuality', 'delete_site_quality_user');
     SET deleted = result.data.deleted;
 %]

=cut

sub delete_site_quality_user ( $args, $result ) {

    my $auth = Cpanel::Koality::Auth->new( timeout => 120 );

    my $deleted = $auth->delete_user();
    if ( !$deleted ) {
        $result->error( locale->maketext("The system could not delete the Site Quality Monitoring user. Try again later.") );
    }
    $result->data( { deleted => $deleted, } );

    return 1;

}

=head2 is_site_quality_user_enabled()

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

Bool that contains if the user is enabled.

=over

=item enabled - bool

True: User has an account and that account is enabled for use.

False: User has an account and that account is not enabled for use.

=back

=head3 EXAMPLES

CLI:

uapi --user=cpanel_user SiteQuality is_site_quality_user_enabled

TT:

 [%
     SET result = execute('SiteQuality', 'is_site_quality_user_enabled');
     SET enabled = result.data.enabled;
 %]

=cut

sub is_site_quality_user_enabled ( $args, $result ) {

    my $auth = Cpanel::Koality::Auth->new();

    my $user = eval { $auth->get_user() };
    if ( my $exception = $@ ) {
        $exception = $_;
        $result->error( locale->maketext("No Site Quality Monitoring user found. You must create a user first.") );
        logger()->error($exception);
        return;
    }

    my $enabled = $user->enabled ? 1 : 0;
    $result->data( { enabled => $enabled } );

    return 1;

}

=head2 get_app_token()

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

Hashref that contains the app token

=over

=item app_token - string

The long-lived application token used to authenticate with the Site Quality Monitoring auth servers.

=back

=head3 EXAMPLES

CLI:

uapi --user=cpanel_user SiteQuality get_app_token

TT:

 [%
     SET result = execute('SiteQuality', 'get_app_token');
     SET token = result.data.app_token;
 %]

=cut

sub get_app_token ( $args, $result ) {

    my ($app_token);
    eval {
        my $user = Cpanel::Koality::User->new();
        $app_token = $user->app_token;
    };
    if ( my $exception = $@ ) {
        $result->error($exception);
        return;
    }

    if ( !$app_token ) {
        $result->error( locale->maketext("No Site Quality Monitoring user found. You must create a user first.") );
        return;
    }

    $result->data( { app_token => $app_token } );
    return 1;
}

=head2 create_project()

=head3 ARGUMENTS

=over

=item name - string - Required

The name of the project to create.

=item url - string - Required

The url to monitor.

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

CLI ( Arguments must be uri escaped ):

uapi --user=cpanel_user SiteQuality create_project name=MyProject url=https%3A%2F%2Fmyurl.com

TT:

 [%
     SET result = execute('SiteQuality', 'create_project',
        { name => 'MyProject', url => 'https://myurl.com' });
     SET projects = result.data.?????;
 %]

=cut

sub create_project ( $args, $result ) {

    my $name              = $args->get_length_required('name');
    my $url               = $args->get_length_required('url');
    my $standard_alerting = $args->get('standard_alerting');
    my $system_type       = $args->get('system_type');

    my $project = {};
    $project->{name}         = $name;
    $project->{url}          = $url;
    $project->{has_alerting} = $standard_alerting if defined $standard_alerting;
    $project->{system_type}  = $system_type       if defined $system_type;

    # Run a fresh auth in case it is stale or it hasn't been run yet.
    my $user = Cpanel::Koality::Auth->new();
    $user->auth_session();

    my $projectid;
    my $systemid;

    my $proj          = Cpanel::Koality::Project->new( timeout => 120 );
    my $proj_response = eval { $proj->create_project($project) };
    if ( my $exception = $@ ) {
        if ( defined Scalar::Util::blessed($exception) && Scalar::Util::blessed($exception) eq 'Cpanel::Exception::HTTP::Server' ) {
            my $content = Cpanel::JSON::Load( $exception->get('content') );
            my $status  = Cpanel::JSON::Load( $exception->get('status') );

            # If we get a 403 status the user does not have any free projects to create.
            # Lets looks for one with a matching url and try to use it.
            if ( $status eq '403' ) {
                my $all_projects = $proj->get_all_projects();
                foreach my $proj_id ( keys $all_projects->%* ) {
                    if ( $all_projects->{$proj_id}{systems}[0]{domain} eq $url ) {
                        $projectid = $proj_id;
                        $systemid  = $all_projects->{$proj_id}{systems}[0]{id};
                        last;
                    }
                }
            }
            else {
                logger()->error( $content->{message} );
                die( $content->{message} );
            }
        }
        else {
            die($@);
        }
    }
    else {
        $projectid = $proj_response->{id};
        $systemid  = $proj_response->{systems}[0]{id};
    }

    die locale->maketext('Failed to find a project ID.') if !$projectid;
    die locale->maketext('Failed to find a system ID.')  if !$systemid;

    # Need to re-auth after project creation to get a new token with new ACL's
    $user->auth_session();

    my $comp          = Cpanel::Koality::Project->new( timeout => 120 );
    my $comp_response = $comp->create_component(
        {
            projectid => $projectid,
            systemid  => $systemid,
            domain    => $url,
        }
    );

    $result->data( { project => $proj_response, component => $comp_response } );

    return 1;
}

=head2 get_all_scores()

=head3 ARGUMENTS

=over

=item verbose - Boolean - Optional

Verbose output will include sub_score results, otherwise only output master scores.

=back

=head3 RETURNS

Arrayref that contains all scores for all systems across all projects owned by the user.

=over

=item scores - Arrayref

An arrayref containing hashrefs with systems and their associated scores.

=back

=head3 EXAMPLES

CLI:

uapi --user=cpanel_user SiteQuality get_all_scores verbose=1

TT:

 [%
     SET result = execute('SiteQuality', 'get_all_scores');
     SET scores = result.data.scores;
 %]

=cut

sub get_all_scores ( $args, $result ) {
    my $verbose = $args->get('verbose') // 0;
    Cpanel::Validate::Boolean::validate_or_die($verbose);

    # Run a fresh auth in case it is stale or it hasn't been run yet.
    my $user    = Cpanel::Koality::Auth->new()->auth_session();
    my $project = Cpanel::Koality::Project->new();

    my $scores = $project->get_all_scores($verbose);

    $result->data( { scores => $scores } );
    return 1;
}

=head2 has_site_quality_user()

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

Bool containing whether or not the cPanel user has a Site Quality Monitoring account.

=over

=item has_site_quality_user - Bool

True: User has an account.

False: User does not have an account.

=back

=head3 EXAMPLES

CLI:

uapi --user=cpanel_user SiteQuality has_site_quality_user

TT:

 [%
     SET result = execute('SiteQuality', 'has_site_quality_user');
     SET token = result.data.app_token;
 %]

=cut

sub has_site_quality_user ( $args, $result ) {

    my ($app_token);
    eval {
        my $user = Cpanel::Koality::User->new();
        $app_token = $user->app_token;
    };
    if ( my $exception = $@ ) {
        $result->error($exception);
        return;
    }

    $result->data( { has_site_quality_user => $app_token ? 1 : 0 } );
    return 1;
}

=head2 get_environment()

=head3 ARGUMENTS

=over

=item None.

=back

=head3 RETURNS

String containing the environment

=over

=item environment - String

staging: When the cPanel Site Quality Monitoring backend uses the staging Koality environment.

production: When the cPanel Site Quality backend uses the production Koality environment.

=back

=head3 EXAMPLES

CLI:

uapi --user=cpanel_user SiteQuality get_environment

TT:

 [%
     SET result = execute('SiteQuality', 'get_environment');
     SET environment = result.data.environment;
 %]

=cut

sub get_environment ( $args, $result ) {
    require Cpanel::Koality::Base;
    my $koality = Cpanel::Koality::Base->new();
    $result->data( { environment => $koality->use_stage ? 'staging' : 'production' } );

    return 1;
}

=head2 verify_code()

=head3 ARGUMENTS

=over

=item code - string - required

=back

=head3 RETURNS

True or false if the code is verified.

=over

=item status - boolean

The status of the verification.

=back

=head3 EXAMPLES

CLI:

uapi --user=cpanel_user SiteQuality verify_code code=1234

TT:

 [%
     SET result = execute('SiteQuality', 'verify_code', { code => '1234' });
     SET status = result.data.status;
 %]

=cut

sub verify_code ( $args, $result ) {

    my $code = $args->get_length_required('code');

    my $auth = Cpanel::Koality::Auth->new();

    # Ensure this is a number and not a string.
    my $verified = $auth->verify_code($code) + 0;

    $result->data( { status => $verified } );

    return 1;
}

=head2 reset_config()

=head3 ARGUMENTS

None.

=head3 RETURNS

The status of the configuration reset.

=over

=item reset - bool

Whether the reset of the config was successful.

=back

=head3 EXAMPLES

CLI:

uapi --user=cpanel_user SiteQuality reset_config

TT:

 [%
     SET result = execute('SiteQuality', 'reset_config');
     SET reset_status = result.data.reset;
 %]

=cut

sub reset_config ( $args, $result ) {

    my $user   = Cpanel::Koality::User->new();
    my $status = $user->reset_config() ? 1 : 0;
    $result->data( { reset => $status } );

    return 1;
}

=head2 send_activation_email()

=head3 ARGUMENTS

None.

=head3 RETURNS

The status of the activation email request.

=over

=item reset - bool

Whether the activation email request was successful.

=back

=head3 EXAMPLES

CLI:

uapi --user=cpanel_user SiteQuality send_activation_email

TT:

 [%
     SET result = execute('SiteQuality', 'send_activation_email');
     SET email_status = result.data.send_activation_email;
 %]

=cut

sub send_activation_email ( $args, $result ) {

    my $auth   = Cpanel::Koality::Auth->new();
    my $status = eval { $auth->send_activation_email() };
    if ( my $exception = $@ ) {
        if ( defined Scalar::Util::blessed($exception) && Scalar::Util::blessed($exception) eq 'Cpanel::Exception::HTTP::Server' ) {
            my $status = Cpanel::JSON::Load( $exception->get('status') );

            # 404 indicates the user not found.
            # We need to let the user know this will
            # never work.
            if ( $status eq '404' ) {
                $result->error( locale->maketext("We cannot create your account right now. Cancel this signup and try again later.") );
                logger()->error($exception);
                return;
            }
        }
        else {
            $result->error( locale->maketext("We could not send your new activation email.") );
            logger()->error($exception);
        }
        return;
    }

    $result->data( { send_activation_email => $status } );

    return 1;
}

1;
