package Whostmgr::Transfers::Session::Items::AccountRemoteUser;

# cpanel - Whostmgr/Transfers/Session/Items/AccountRemoteUser.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = '1.2';

use Cpanel::AcctUtils::Domain         ();
use Cpanel::Config::HasCpUserFile     ();
use Cpanel::Config::LoadCpUserFile    ();
use Cpanel::Config::LoadWwwAcctConf   ();
use Cpanel::FileUtils::Path           ();
use Cpanel::AccessIds                 ();
use Cpanel::DIp::IsDedicated          ();
use Cpanel::Exception                 ();
use Cpanel::NameserverCfg             ();
use Cpanel::NAT                       ();
use Cpanel::SafeRun::Object           ();
use Cpanel::PwCache                   ();
use Cpanel::CPAN::IO::Callback::Write ();
use Cpanel::RDAP::URL                 ();

use Whostmgr::Passwd::Change         ();
use Whostmgr::Transfers::MysqlStream ();

# Give ourselves 24 hours to use the token.
use constant {
    _CP_TOKEN_VALIDITY_LENGTH => 86400,
    _IS_ROOT_USABLE           => 0,
    _IS_USER_USABLE           => 1,
    _PRIVILEGE_LEVEL          => 'user',
    _LIVE_TRANSFER_FLAG_NAME  => 'live_transfer',
};

use parent qw(
  Cpanel::Parser::Line
  Whostmgr::Transfers::Session::Items::AccountRemoteBase
);

our $TRANSFER_TIMEOUT = ( 26 * 60 * 60 );                              # 26 hours
our $READ_TIMEOUT     = ( 15 * 60 );                                   # 15 min
our $MOVE_SCRIPT      = "/usr/local/cpanel/scripts/getremotecpmove";

sub transfer {
    my ($self) = @_;

    return $self->exec_path(
        [
            qw(
              _transfer_init
              _validate_local_account_username_available
              _getremotecpmove
              _save_results_to_session
            )
        ],
        undef,
        $Whostmgr::Transfers::Session::Item::ABORTABLE,
    );
}

sub _save_results_to_session {
    my ($self) = @_;

    my $restorefile = 'cpmove-' . $self->_username() . '.tar.gz';
    my $restoredir  = '/home';
    if ( $self->{'remote_file_path'} ) {
        ( $restoredir, $restorefile ) = Cpanel::FileUtils::Path::dir_and_file_from_path( $self->{'remote_file_path'} );
    }

    my $ok =
         $self->set_key( 'detected_remote_user', $self->_username() )
      && $self->set_key( 'copypoint',            $restoredir )
      && $self->set_key( 'cpmovefile',           $restorefile );

    if ( !$ok ) {
        return ( 0, $self->_locale()->maketext("Failed to save the result of the transfer to the session database.") );
    }
    return ( 1, "Saved resulted to session database." );

}

sub _transfer_init {
    my ($self) = @_;

    $self->session_obj_init();

    return $self->validate_input( [ qw(session_obj options authinfo remote_info output_obj), [ 'input', ['ip'] ], [ 'authinfo', ['pass'] ] ] );
}

#----------------------------------------------------------------------
# Aliases for legibility

*_username = __PACKAGE__->can('item');

sub _remote_hostname ($self) {
    return $self->{'remote_info'}->{'host'} || die 'Need remote_info.host!';
}

sub _remote_password ($self) {
    return $self->{'authinfo'}->{'pass'};
}

#----------------------------------------------------------------------

sub _getremotecpmove {
    my ($self) = @_;

    print $self->_locale()->maketext(
        "Attempting to copy “[_1]” from “[_2]”.",
        $self->_username(),
        $self->_remote_hostname(),
    ) . "\n";

    $self->{'output_obj'}->set_source( { 'host' => $self->_remote_hostname() } );
    $self->{'goodmove'} = 0;
    my $errlog = '';
    my $run    = Cpanel::SafeRun::Object->new(
        'program'      => $MOVE_SCRIPT,
        'args'         => [ $self->_remote_hostname(), $self->_username() ],
        'stdout'       => Cpanel::CPAN::IO::Callback::Write->new( sub { $self->process_data( $_[0] ); } ),
        'stderr'       => Cpanel::CPAN::IO::Callback::Write->new( sub { $errlog .= $_[0]; print STDERR $_[0]; } ),
        'stdin'        => ( $self->_remote_password() || '' ),
        'read_timeout' => $READ_TIMEOUT,
        'timeout'      => $TRANSFER_TIMEOUT,
    );

    if ( !$run ) {
        return ( 0, $self->_locale()->maketext( "Unable to execute “[_1]”.", $MOVE_SCRIPT ) );
    }
    elsif ( $run->CHILD_ERROR() || $run->timed_out() ) {
        return ( 0, $self->_locale()->maketext( "Error while executing “[_1]”. [_2]: [_3]", $MOVE_SCRIPT, $run->autopsy(), $errlog ) );
    }

    $self->{'output_obj'}->set_source();

    if ( !$self->{'goodmove'} ) {
        return ( 0, $self->_locale()->maketext('Error while copying account. Aborting extraction.') );
    }

    return ( 1, 'Copy OK' );
}

sub process_line {
    my ( $self, $line ) = @_;

    if ( $line =~ m{Attempting} ) {
        $self->set_percentage(10);
    }
    elsif ( $line =~ m{Waiting for backup to start} ) {
        $self->set_percentage(20);
    }
    elsif ( $line =~ m{wait cycle} ) {
        $self->set_percentage(25);
    }
    elsif ( $line =~ m{polling}i ) {
        $self->set_percentage(35);
    }
    elsif ( $line =~ m{content-length}i ) {
        $self->set_percentage(60);
    }
    elsif ( $line =~ m/pkgacctfile is: (\S+)/i ) {
        $self->set_percentage(80);
        $self->{'remote_file_path'} = $1;
    }
    elsif ( $line =~ m/MOVE IS GOOD/ ) {
        $self->{'goodmove'} = 1;
    }
    else {
        print $line;
    }

    return 1;
}

sub _validate_local_account_username_available ($self) {
    return $self->_validate_local_username_against_system_state( $self->_username() );
}

sub post_restore {
    my ($self) = @_;

    my ( $post_restore_ok, $post_restore_msg ) = $self->_validate_post_restore_options();

    return ( $post_restore_ok, $post_restore_msg ) if !$post_restore_ok;

    $self->_remove_used_package_scripts();

    $self->_restore_account_password();

    $self->_delete_api_token_if_needed();

    return ( 1, "Post restore successful." );

}

sub _validate_post_restore_options {
    my ($self) = @_;
    foreach my $required_object (qw(session_obj options authinfo remote_info output_obj)) {
        if ( !defined $self->{$required_object} ) {
            return ( 0, $self->_locale()->maketext( "“[_1]” failed to create “[_2]”.", ( caller(0) )[3], $required_object ) );
        }
    }
    return ( 1, 'Validated' );
}

sub _remove_used_package_scripts {
    my ($self) = @_;

    my $user_homedir = ( Cpanel::PwCache::getpwnam( $self->_username() ) )[7];
    if ( length($user_homedir) > 4 ) {
        Cpanel::AccessIds::do_as_user(
            $self->_username(),
            sub { system( '/bin/rm', '-rf', '--', "$user_homedir/pkgacct", "$user_homedir/public_html/cgi-bin/cpdownload" ) }
        );
    }

    return 1;
}

sub _restore_account_password {
    my ($self) = @_;

    my ( $result, $output, $passout, $services ) = Whostmgr::Passwd::Change::passwd( $self->_username(), $self->_remote_password() );
    if ($result) {
        print $self->_locale()->maketext( "The password for “[_1]” has been changed without results: “[_2]”.", $self->_username(), $passout ) . "\n";
        if ( ref $services eq 'ARRAY' ) {
            my ( @GOODSRVS, @BADSRVS );
            foreach my $srv ( @{$services} ) {
                push @GOODSRVS, $srv->{'app'};
            }

            # @BADSRVS is NOT IMPLEMENTED at this time, however in the event we do implement this in the future
            # this conforms to all the other calls we make to Whostmgr::Passwd::Change::passwd
            if (@BADSRVS) {
                print $self->_locale()->maketext( "The following service passwords failed to change: “[_1]”.", join( ' , ', @BADSRVS ) ) . ".\n";
            }
            if (@GOODSRVS) {
                print $self->_locale()->maketext( "The following service passwords were changed: “[_1]”.", join( ' , ', @GOODSRVS ) ) . ".\n";
            }
        }
    }
    else {
        print $self->_locale()->maketext( "The password for “[_1]” could not be changed because: “[_2]”.", $self->_username(), $output ) . "\n";
    }
    return ( 1, 'Password restored' );
}

sub _get_uapi ($self) {
    return $self->{'_uapi'} ||= do {
        require Cpanel::RemoteAPI::cPanel;

        Cpanel::RemoteAPI::cPanel->new_from_password(
            $self->_remote_hostname(),
            $self->_username(),
            $self->_remote_password(),
        )->disable_tls_verify();
    };
}

sub _can_stream_mysql ($self) {
    return $self->_get_uapi()->get_cpanel_version_or_die() >= Whostmgr::Transfers::MysqlStream::MINIMUM_CP_VERSION();
}

sub _can_stream_homedir ($self) {

    # Versions prior to 93 had the facility for streaming but lacked
    # the wiring in scripts/getremotecpmove to omit the homedir.
    return $self->_get_uapi()->get_cpanel_version_or_die() >= 93;
}

sub _prevalidate_live_transfer ( $class, $session_obj, $input_hr ) {

    return if !$input_hr->{ _LIVE_TRANSFER_FLAG_NAME() };

    my $username      = $input_hr->{'user'};
    my $remoteinfo_hr = $session_obj->remoteinfo();
    my $authinfo_hr   = $session_obj->authinfo();

    my $hostname = $remoteinfo_hr->{'host'};
    my $password = $authinfo_hr->{'pass'};

    require Cpanel::RemoteAPI::cPanel;
    my $api_obj = Cpanel::RemoteAPI::cPanel->new_from_password(
        $hostname,
        $username,
        $password,
    )->disable_tls_verify();

    my $cpversion = "11." . $api_obj->get_cpanel_version_or_die();

    require Cpanel::Version::Support;

    if ( !Cpanel::Version::Support::version_supports_feature( $cpversion, 'user_live_transfers' ) ) {
        my $min = Cpanel::Version::Support::get_minimum_version('user_live_transfers');
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” option requires a source server that runs [asis,cPanel amp() WHM] version “[_2]” or greater. “[_3]” runs version “[_4]”.', [ _LIVE_TRANSFER_FLAG_NAME, $min, $hostname, $cpversion ] );
    }

    return;
}

sub _run_remote_xferpoint {

    my ( $self, @other_domains ) = @_;

    my $creator = 'root';
    if ( Cpanel::Config::HasCpUserFile::has_cpuser_file( $self->{'local_user'} ) ) {
        my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile( $self->{'local_user'} );
        if ( $cpuser_ref->{'OWNER'} ) { $creator = $cpuser_ref->{'OWNER'}; }
    }
    my $primary_domain  = Cpanel::AcctUtils::Domain::getdomain( $self->{'local_user'} );
    my @new_nameservers = Cpanel::NameserverCfg::fetch($creator);

    require Cpanel::DomainIp;
    my $domainip          = Cpanel::DomainIp::getdomainip($primary_domain);
    my $newip             = Cpanel::NAT::get_public_ip($domainip);
    my $shared_ip_address = Cpanel::NAT::get_public_ip( Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf()->{'ADDR'} );
    my $ftpip             = Cpanel::DIp::IsDedicated::isdedicatedip($domainip) ? $newip : $shared_ip_address;

    my $api_client = $self->_get_uapi();

    my $output_obj = $self->{'output_obj'} or die 'need output_obj';

    my $output_cr = sub ( $level, $txt ) {
        my $msg_struct = _format_message_for_output_obj($txt);

        $output_obj->$level($msg_struct);
    };

    $output_cr->( 'out', $self->_locale()->maketext('Updating [asis,IP] addresses in the source server’s [asis,DNS] zones …') );

    my $swap_ip_result = $api_client->request_uapi(
        'DNS', 'swap_ip_in_zones',
        {
            'source_ip' => -1,
            'dest_ip'   => $newip,
            'ftp_ip'    => $ftpip,
            'domain'    => [ $primary_domain, @other_domains ],
        }
    );
    if ( !$swap_ip_result->status() ) {
        $output_cr->( 'warn', "Failed to swap IPs: " . $swap_ip_result->errors_as_string() );
    }

    my $need_feature = 'zoneedit';

    my $has_features_result = $api_client->request_uapi(
        'Features', 'has_feature', { name => $need_feature },
    );

    my $should_try_to_update_zones;

    if ( !$has_features_result->status() ) {
        $output_cr->( 'warn', "Failed to determine if source account has the “$need_feature” feature; proceeding anyway …" );
        $should_try_to_update_zones = 1;
    }
    else {
        $should_try_to_update_zones = $has_features_result->data();

        if ($should_try_to_update_zones) {
            $output_cr->( 'out', $self->_locale()->maketext( 'The source account can edit [list_and_quoted,_1] [asis,DNS] records. The system will update those records as needed.', [ 'SOA', 'NS' ] ) );
        }
        else {
            $output_cr->( 'warn', $self->_locale()->maketext( 'The source account cannot edit [list_or_quoted,_1] [asis,DNS] records. Because of this, the system cannot redirect [asis,DNS] queries from the source server’s [asis,DNS] cluster.', [ 'SOA', 'NS' ] ) );
        }
    }

  ZONE:
    foreach my $domain ( $primary_domain, @other_domains ) {
        $output_cr->( 'out', $self->_locale()->maketext( 'Fetching “[_1]”’s [list_and_quoted,_2] [asis,DNS] records …', $domain, [ 'SOA', 'NS' ] ) );

        my $fetch_zone_result = _request_api2_or_warn(
            $api_client,
            'fetchzone',
            {
                'domain' => $domain,
                'type'   => 'SOA|NS',
            },
            $output_cr,
        );

        if ( my $err = $fetch_zone_result->{'error'} ) {
            $output_cr->( 'warn', "Failed to fetch records: $err" );
            next ZONE;
        }

        my $fetch_zone_records = $fetch_zone_result->{'data'}[0]{'record'};

        my ($soa_record) = grep { $_->{'type'} eq 'SOA' } @{$fetch_zone_records};

        my @ns_records = grep { $_->{'type'} eq 'NS' } @{$fetch_zone_records};

        my ($ns_ttl) = map { $_->{'ttl'} } @ns_records;

        # Just in case there somehow were no NS records before …
        $ns_ttl ||= 14400;

        my @nsnames = map { $_->{'nsdname'} } @ns_records;

        my ( @adds, @edits, @removes );

        if ( $soa_record->{'mname'} ne $new_nameservers[0] ) {
            push @edits, {
                'domain' => $domain,
                'line'   => $soa_record->{'Line'},
                'mname'  => $new_nameservers[0],
            };
        }

        if ( "@nsnames" ne "@new_nameservers" ) {
            $output_cr->( 'out', $self->_locale()->maketext( 'Update “[_1]”’s name servers at that domain’s registrar to [list_and_quoted,_2]. See [output,url,_3] for this domain’s registrar information.', $domain, \@new_nameservers, Cpanel::RDAP::URL::get_for_domain($domain) ) );

            my @old_records = @ns_records;
            my @new_names   = @new_nameservers;

            while ( my $new_name = shift @new_names ) {
                if ( my $old_record = shift @old_records ) {
                    push @edits, {
                        domain  => $domain,
                        line    => $old_record->{'Line'},
                        nsdname => $new_name,
                    };
                }
                else {
                    push @adds, {
                        'domain'  => $domain,
                        'name'    => "$domain.",
                        'type'    => 'NS',
                        'nsdname' => $new_name,
                        'ttl'     => $ns_ttl,
                    };
                }
            }

            for my $old_record (@old_records) {
                push @removes, {
                    'domain' => $domain,
                    'line'   => $old_record->{'Line'},
                };
            }
        }

        if ( !@adds && !@edits && !@removes ) {
            $output_cr->( 'out', $self->_locale()->maketext( '“[_1]” requires no [asis,DNS] zone updates on the source server.', $domain ) );
            next ZONE;
        }
        elsif ( !$should_try_to_update_zones ) {
            $output_cr->( 'out', $self->_locale()->maketext( '“[_1]” requires [asis,DNS] zone updates on the source server, but the account lacks the authorization to make those updates.', $domain ) );
            next ZONE;
        }

        $output_cr->( 'out', $self->_locale()->maketext( 'Updating “[_1]” on the source server …', $domain ) );

        for my $item_hr (@adds) {
            _request_api2_or_warn( $api_client, 'add_zone_record', $item_hr, $output_cr );
        }

        for my $item_hr (@edits) {
            _request_api2_or_warn( $api_client, 'edit_zone_record', $item_hr, $output_cr );
        }

        for my $item_hr (@removes) {
            _request_api2_or_warn( $api_client, 'remove_zone_record', $item_hr, $output_cr );
        }
    }

    return 1;
}

sub _request_api2_or_warn ( $api_client, $fn, $args_hr, $output_cr ) {    ## no critic qw(ManyArgs) - mis-parse
    my $resp_hr = $api_client->request_api2(
        'ZoneEdit', $fn, $args_hr,
    );

    if ( my $err = $resp_hr->{'error'} ) {
        $output_cr->( 'warn', "ZoneEdit::$fn failed: $err" );
        return undef;
    }

    return $resp_hr;
}

sub _get_api_token ($self) {
    return $self->{'_api_token'} ||= do {
        require Cpanel::RemoteAPI::cPanel::TemporaryToken;

        $self->{'_temp_token_obj'} = Cpanel::RemoteAPI::cPanel::TemporaryToken->new(
            api             => $self->_get_uapi(),
            prefix          => 'cpmove',
            validity_length => _CP_TOKEN_VALIDITY_LENGTH(),
        );

        $self->{'_temp_token_obj'}->get();
    };
}

sub _get_remote_cpversion ($self) {
    my $api_client = $self->_get_uapi();

    return "11." . $api_client->get_cpanel_version_or_die();
}

sub _delete_api_token_if_needed ($self) {
    delete $self->{'_temp_token_obj'};

    return;
}

sub _custom_account_restore_args ($self) {
    my @args;

    if ( $self->_can_stream_mysql() ) {
        print $self->_locale()->maketext( '“[_1]” supports [asis,MySQL®] streaming.', $self->_remote_hostname() );

        push @args, (
            'mysql_stream' => {
                method => 'plain',

                $self->_stream_creds(),
            },
        );
    }
    else {
        print $self->_locale()->maketext( '“[_1]” does not support [asis,MySQL®] streaming.', $self->_remote_hostname() );
    }

    if ( $self->_can_stream_homedir() ) {
        print $self->_locale()->maketext( '“[_1]” supports home directory streaming.', $self->_remote_hostname() );

        push @args, (
            'homedir_stream' => {
                $self->_stream_creds(),
            },
        );
    }
    else {
        print $self->_locale()->maketext( '“[_1]” does not support home directory streaming.', $self->_remote_hostname() );
    }

    push @args, (
        'remote_api_token'          => $self->_get_api_token(),
        'remote_hostname'           => $self->_remote_hostname(),
        'remote_host'               => $self->_remote_hostname(),
        'remote_cpversion'          => $self->_get_remote_cpversion(),
        'remote_api_token_username' => $self->_username(),
    );

    return @args;
}

sub _format_message_for_output_obj ($textmsg) {
    return { msg => [$textmsg] };
}

sub _stream_creds ($self) {
    return (
        host               => $self->_remote_hostname(),
        api_token_username => $self->_username(),
        api_token          => $self->_get_api_token(),
        application        => 'cpanel',
    );
}

1;
