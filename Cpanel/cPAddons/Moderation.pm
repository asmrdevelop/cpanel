
# cpanel - Cpanel/cPAddons/Moderation.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Moderation;

use strict;
use warnings;

use Cpanel::AcctUtils::Owner   ();
use Cpanel::AdminBin           ();
use Cpanel::Config::LoadCpConf ();
use Cpanel::Hostname           ();
use Cpanel::PwCache            ();
use Cpanel::Template           ();
use Cpanel::Validate::EmailRFC ();
use Cpanel::cPAddons::Notices  ();
use Cpanel::Encoder::Tiny      ();
use Cpanel                     ();
use Cpanel::Imports;
use Cpanel::cPAddons::Cache ();
use Cpanel::cPAddons::Util  ();
use Cpanel::Locale          ();

=head1 NAME

Cpanel::cPAddons::Moderation

=head1 DESCRIPTION

Utility module that handles moderation data management.

=head1 METHODS


=head2 get_moderated_modules()

Prepares the system to support processing of moderation requests.

=cut

sub assert_prerequisites {
    my ( $user, $homedir ) = @_;
    my $error;
    Cpanel::cPAddons::Util::must_not_be_root('Manipulates directories under homedir');

    my $path = "$homedir/.cpaddons/";
    if ( !-d $path ) {
        if ( !mkdir $path ) {
            my $exception = $!;
            $error = locale()->maketext(
                'The system could not create user’s [_1] directory for [_2]: [_3]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($path),
                Cpanel::Encoder::Tiny::safe_html_encode_str($user),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            );
            logger()->warn("Unable to create $path directory for $user: $exception");
            Cpanel::cPAddons::Notices::singleton()->add_error($error);
            return $error;
        }
    }

    $path = "$homedir/.cpaddons/moderation/";
    if ( !-d $path ) {
        if ( !mkdir $path ) {
            my $exception = $!;
            $error = locale()->maketext(
                'The system could not create user’s [_1] directory for [_2]: [_3]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($path),
                Cpanel::Encoder::Tiny::safe_html_encode_str($user),
                Cpanel::Encoder::Tiny::safe_html_encode_str($exception),
            );
            logger()->warn("Unable to create $path directory for $user: $exception");
            Cpanel::cPAddons::Notices::singleton()->add_error($error);
            return $error;
        }
    }

    return;
}

=head2 get_moderated_modules()

Loads the moderation YAML file at /var/cpanel/cpaddons_moderated.yaml.

Returns a hash ref containing:

- moderated - Hash ref - The data from the moderation YAML file, which is structured like this, with each
true value indicating that the cPAddon in question is being moderated:

  {
      MODULE_NAME_A => 1, # See the MODULE NAMES section of Cpanel::cPAddons::Module for more info on module names
      MODULE_NAME_B => 1,
  }

=cut

sub get_moderated_modules {

    my $moderated = {};
    my $response  = {
        moderated => {},
    };

    if ( _exists('/var/cpanel/cpaddons_moderated.yaml') ) {
        if ( !Cpanel::cPAddons::Cache::read_cache( '/var/cpanel/cpaddons_moderated.yaml', $moderated ) ) {
            $response->{error} = "Moderation detected but unreadable, Aborting. Contact your server admin!";
            return $response;
        }
        else {
            $response->{moderated} = $moderated;
        }
    }
    return $response;
}

=head2 is_moderated(MODULE)

Check whether a module is moderated.

=head3 Arguments

MODULE - String - The cPAddons module name. See the MODULE NAMES section of B<perldoc Cpanel::cPAddons::Module> for more info.

=head3 Returns

A hash ref containing:

- is_moderated - Boolean - True if moderated; otherwise false.

- error - String - (Only on failure) The error message.

=cut

sub is_moderated {
    my ($module) = @_;

    my $response = Cpanel::cPAddons::Moderation::get_moderated_modules();
    if ( $response->{error} ) {
        return $response;
    }

    $response->{is_moderated} = exists $response->{moderated}{$module};
    delete $response->{moderated};

    return $response;
}

=head2 is_approved(MODULE)

Check whether the moderation request has been approved by the server administrator.

B<Important>: Do not run this function as root. If you do, you will enable other users on
the system to perform symlink attacks.

=head3 Arguments

- MODULE - String - The cPAddons module to check

=head3 Returns

A hash ref containing:

- user - String - The current user

- module - String - The module that was passed in

- approved - Boolean - Whether the request has been approved

- error - String - (Only on failure) The error message

=cut

sub is_approved {
    my ($module) = @_;

    Cpanel::cPAddons::Util::must_not_be_root('Symlink attack: Reads from file under homedir');

    my $user    = $Cpanel::user;
    my $homedir = $Cpanel::homedir;

    my $response = list_moderation_requests($user);
    return $response if $response->{error};

    my $moderation_requests = $response->{requests};

    $response = {
        user     => $user,
        module   => $module,
        approved => 0,
    };

    if ( $response->{error} = assert_prerequisites( $user, $homedir ) ) {
        return $response;
    }

    for my $request (@$moderation_requests) {
        my $requests      = {};
        my $requests_path = "$homedir/.cpaddons/moderation/$request";
        if ( Cpanel::cPAddons::Cache::read_cache( $requests_path, $requests, $user ) ) {
            next if !exists $requests->{'res'};
            if ( $requests->{'res'} > 0 ) {
                my $approvals     = {};
                my $approval_path = "/var/cpanel/cpaddons_moderation/$requests->{res}";
                if ( Cpanel::cPAddons::Cache::read_cache( $approval_path, $approvals ) ) {
                    if ( $approvals->{'ok'} ) {
                        next if $approvals->{'requser'} ne $user;
                        next if $approvals->{'mod'} ne $module;
                        $response->{approved} = 1;
                        $response->{perm_ok}  = $approvals->{'permanent'};
                        $response->{id}       = $request;
                        last;
                    }
                }
                else {
                    my $error = locale()->maketext(
                        'The system could not load the moderation approvals from the following path: [_1]',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($approval_path),
                    );
                    logger()->warn("Could not load moderation approvals from: $approval_path.");
                    Cpanel::cPAddons::Notices::singleton()->add_error($error);
                    $response->{error} = $error;
                }
            }
        }
        else {
            my $error = locale()->maketext(
                'The system could not load moderation requests from the following path: [_1]',
                Cpanel::Encoder::Tiny::safe_html_encode_str($requests_path),
            );
            logger()->warn("Could not load moderation requests at: $requests_path.");
            Cpanel::cPAddons::Notices::singleton()->add_error($error);
            $response->{error} = $error;
        }
    }

    return $response;
}

=head2 list_moderation_requests(USER)

List the pending moderation requests for the current user.

=head3 Arguments

- USER - String - (Optional) The user for which to check. If not specified, defaults to the current user. B<DO NOT USE> - Unsafe - May be removed in future changes.

=head3 Returns

A hash ref containing:

- user - String - The current user

- requests - Array ref - The pending moderation requests for the current user. Each entry is a string with the name of the YAML file for the moderation request.

- error - String - (Only on failure) The error message

=cut

sub list_moderation_requests {
    my ($user) = @_;
    $user = $Cpanel::user if !$user;

    Cpanel::cPAddons::Util::must_not_be_root('Calls assert_prerequisites, which manipulates directories under homedir');

    my $homedir =
        $user eq $Cpanel::user
      ? $Cpanel::homedir
      : ( getpwnam $user )[7];

    my $response = {
        user     => $user,
        requests => [],
    };

    if ( $response->{error} = assert_prerequisites( $user, $homedir ) ) {
        return $response;
    }

    if ( opendir my $mdt, "$homedir/.cpaddons/moderation/" ) {

        if ( !$mdt ) {
            $response->{error} = 'Moderation detected but unreadable. Aborting. Contact your server administrator.';
            return $response;
        }
        $response->{requests} = [ grep /\.\d+\.yaml$/, readdir $mdt ];
        closedir $mdt;
    }
    else {
        $response->{error} = 'Moderation detected but unreadable. Aborting. Contact your server administrator.';
        return $response;
    }
    return $response;
}

sub list_module_moderation_requests {
    my ( $module, $user ) = @_;
    my $response = list_moderation_requests($user);
    $response->{module}          = $module;
    $response->{module_requests} = [];

    return $response if $response->{error};

    $response->{module_requests} = [ grep /^\Q$module\E\.\d+\.yaml$/, @{ $response->{requests} } ];
    return $response;
}

sub has_reached_max_moderation_req_all_mod {
    my ($user) = @_;

    my $response = list_moderation_requests($user);
    if ( $response->{error} ) {
        die $response->{error};
    }

    my $cpconf_ref = %Cpanel::CONF ? \%Cpanel::CONF : Cpanel::Config::LoadCpConf::loadcpconf();

    my $max_moderation_req_all_mod =
      exists $cpconf_ref->{'cpaddons_max_moderation_req_all_mod'} && $cpconf_ref->{'cpaddons_max_moderation_req_all_mod'} ne ''
      ? $cpconf_ref->{'cpaddons_max_moderation_req_all_mod'}
      : 99;
    my $current_moderation_requests = scalar @{ $response->{'requests'} };
    if ( $current_moderation_requests < $max_moderation_req_all_mod ) {
        return 0;
    }
    return 1;
}

sub has_reached_max_moderation_req_per_mod {
    my ( $module, $user ) = @_;

    my $num_requests = list_module_moderation_requests( $module, $user );
    if ( $num_requests->{error} ) {
        die $num_requests->{error};
    }

    my $cpconf_ref = %Cpanel::CONF ? \%Cpanel::CONF : Cpanel::Config::LoadCpConf::loadcpconf();

    my $max_moderation_req_per_mod =
      exists $cpconf_ref->{'cpaddons_max_moderation_req_per_mod'} && $cpconf_ref->{'cpaddons_max_moderation_req_per_mod'} ne ''
      ? $cpconf_ref->{'cpaddons_max_moderation_req_per_mod'}
      : 99;
    if ( scalar @{ $num_requests->{'module_requests'} } < $max_moderation_req_per_mod ) {
        return 0;
    }
    return 1;
}

=head3 create_moderation_request(MOD, INPUT)

Create a new moderation request.

=head3 Arguments

- MOD - String - The module name for which to create a moderation request

- INPUT - Hash ref - The form data from the user submission

=head3 Returns

Hash ref containing:

- notices - Cpanel::cPAddons::Notices object - Any notices generated during the creation
of the moderation request will be stored here. This object can also be used to determine
the success or failure of the operation. See B<perldoc Cpanel::cPAddons::Notices> for
more info.

=cut

sub create_moderation_request {
    my ( $mod, $input ) = @_;

    Cpanel::cPAddons::Util::must_not_be_root('Symlink attack: Writes to file under homedir');

    my $notices  = Cpanel::cPAddons::Notices::singleton();
    my $response = {
        notices => $notices,
    };

    if ( Cpanel::cPAddons::Moderation::has_reached_max_moderation_req_all_mod() ) {
        $notices->add_error( locale()->maketext('You exceeded the maximum [asis,cPAddon] Moderation Request limit.') );
    }
    elsif ( Cpanel::cPAddons::Moderation::has_reached_max_moderation_req_per_mod($mod) ) {
        $notices->add_error( locale()->maketext( 'You exceeded the maximum [asis,cPAddon] Moderation Request limit for [_1].', Cpanel::Encoder::Tiny::safe_html_encode_str($mod) ) );
    }
    else {
        my $uniq = 0;
        $input->{'action'} = 'install';
        $input->{'asuser'} = $Cpanel::user;

        # Get an unused slot
        while ( -e "$Cpanel::homedir/.cpaddons/moderation/$mod.$uniq.yaml" ) { $uniq++; }

        # Copy the hash
        my %input_hash = %{$input};

        my $moderation_name = "$Cpanel::homedir/.cpaddons/moderation/$mod.$uniq";
        if (
            Cpanel::cPAddons::Cache::write_cache(
                $moderation_name,
                {
                    'input_hr' => \%input_hash,
                    'date'     => time(),
                    'msg'      => $input->{'request_note'},
                    'res'      => 0
                }
            )
        ) {

            if ( -z "$moderation_name.yaml" ) {

                # it was created but is empty, probably over quota:
                $notices->add_error(
                    locale()->maketext(
                        'The system could not create the moderation request: [_1]',
                        Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                    )
                );
                if ( !unlink "$moderation_name.yaml" ) {
                    $notices->add_error(
                        locale()->maketext(
                            "The system could not unlink the [_1] file: [_2]",
                            Cpanel::Encoder::Tiny::safe_html_encode_str("$moderation_name.yaml"),
                            Cpanel::Encoder::Tiny::safe_html_encode_str($!)
                        )
                    );
                }
            }
            else {
                $input->{'action'} = 'sendmodreq';
                if ( !chmod 0600, "$moderation_name.yaml" ) {
                    $notices->add_error(
                        locale->maketext(
                            'The system could not chmod “[_1]” to “[_2]” because of the following error: “[_3]”. You must correct the file permissions manually.',
                            Cpanel::Encoder::Tiny::safe_html_encode_str("$moderation_name.yaml"),
                            600,
                            Cpanel::Encoder::Tiny::safe_html_encode_str($!),
                        )
                    );
                }

                if ( has_moderation_request_notify() ) {

                    # TODO: Consider move admin contact lookup to UTILS?
                    my $owner = Cpanel::AcctUtils::Owner::getowner($Cpanel::user);
                    my $resellercontactemail;
                    if ( $owner && $owner ne 'root' ) {
                        my $reseller_homedir = ( Cpanel::PwCache::getpwnam($owner) )[7];
                        if ( $reseller_homedir && -e $reseller_homedir ) {
                            my ( $cruft, $email ) = split( /\s+/, Cpanel::AdminBin::adminrun( 'reseller', 'GETCONTACTEMAIL', 0 ) );
                            if ( $email && Cpanel::Validate::EmailRFC::is_valid($email) ) {
                                $resellercontactemail = $email;
                            }
                        }
                    }

                    my $admincontactemail = $resellercontactemail || $Cpanel::cPAddons::Globals::admincontactemail;

                    my $hostname = Cpanel::Hostname::gethostname();
                    require Cpanel::Redirect;
                    my $url_host = Cpanel::Redirect::getserviceSSLdomain('cpanel') || $hostname;

                    my ( $ok, $output ) = Cpanel::Template::process_template(
                        'cpanel',
                        {
                            template_file     => 'addoncgi/notices/moderationrequest.tt',
                            print             => 0,
                            admincontactemail => $admincontactemail,
                            form              => $input,
                            hostname          => $hostname,
                            user              => $Cpanel::user,
                            url               => "https://$url_host:2087/cgi/cpaddons_report.pl",
                            module            => {
                                name => $mod,
                            },
                        }
                    );

                    if ( $ok && open( my $sendmail_fh, '|/usr/sbin/sendmail -t' ) ) {    ## no critic(ProhibitTwoArgOpen)
                        print {$sendmail_fh} $$output;
                        close $sendmail_fh;
                    }

                }
                $notices->add_success( locale()->maketext('The system sent your request. You will receive an email at your contact address or [asis,cPanel] account after the admin responds to your request.') );
            }
        }
        else {
            my $exception = $!;
            $notices->add_error( locale()->maketext( 'Could not create request! [_1]', Cpanel::Encoder::Tiny::safe_html_encode_str($exception) ) );
        }

    }
    return $response;
}

sub has_moderation_request_notify {

    my $cpconf_ref = %Cpanel::CONF ? \%Cpanel::CONF : Cpanel::Config::LoadCpConf::loadcpconf();
    my $moderation_request_notify =
      exists $cpconf_ref->{'cpaddons_moderation_request'} && $cpconf_ref->{'cpaddons_moderation_request'} ne ''
      ? $cpconf_ref->{'cpaddons_moderation_request'}
      : 0;    # 0 is off
    return $moderation_request_notify;
}

sub _exists {
    my ($path) = @_;
    return -e $path;
}

1;
