package Whostmgr::Transfers::ConvertAddon::MigrateData::EA4Configuration;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/EA4Configuration.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Try::Tiny;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData);

use Cpanel::JSON                         ();
use File::Basename                       ();
use Cpanel::PwCache                      ();
use Cpanel::ProgLang                     ();
use Cpanel::TempFile                     ();
use Cpanel::Exception                    ();
use Cpanel::WebServer                    ();
use Cpanel::Config::Httpd::EA4           ();
use Cpanel::FileUtils::Write             ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::WebServer::Userdata          ();

sub new {
    my ( $class, $opts ) = @_;

    my $self = $class->SUPER::new($opts);
    $self->{'is_ea4'} = Cpanel::Config::Httpd::EA4::is_ea4() ? 1 : 0;

    return $self;
}

sub is_ea4 { return shift->{'is_ea4'} }

sub fetch_php_version_for_domain {
    my ( $self, $opts_hr ) = @_;

    _validate_required_params( 'fetch_php_version_for_domain', $opts_hr );

    $self->_populate_phpinfo($opts_hr) or return;

    my @version = split /\./, $self->{'phpinfo'}->{'php_version'};
    return 'ea-php' . join '', @version[ 0 .. 1 ];
}

sub set_php_version_for_domain {
    my ( $self, $opts_hr ) = @_;

    $self->ensure_users_exist();
    _validate_required_params( 'set_php_version_for_domain', $opts_hr );

    my $success = 0;
    try {
        # write it to the .htacess so it takes effect immediately, wirte it to userdata so it sticks
        my $php      = Cpanel::ProgLang->new( type => 'php' );
        my $ws       = Cpanel::WebServer->new();
        my $userdata = Cpanel::WebServer::Userdata->new( user => $self->{'to_username'} );
        $ws->set_vhost_lang_package( userdata => $userdata, 'user' => $self->{'to_username'}, 'vhost' => $opts_hr->{'domain'}, 'lang' => $php, 'package' => $opts_hr->{'phpversion'} );    # dies

        $success = 1;
    }
    catch {
        $self->add_warning( 'Failed to set PHP version for the domain: ' . Cpanel::Exception::get_string_no_id($_) );
    };

    return $success;
}

sub save_php_configuration {
    my $self = shift;
    $self->ensure_users_exist();

    try {
        my ( $to_user_uid, $to_user_gid, $to_user_homedir ) = ( Cpanel::PwCache::getpwnam( $self->{'to_username'} ) )[ 2, 3, 7 ];
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                my $php_ini;
                my $php_data = $self->_parse_phpinfo();
                foreach my $section ( sort keys %{$php_data} ) {
                    $php_ini .= "[$section]\n";
                    foreach my $key ( keys %{ $php_data->{$section} } ) {
                        my $value = $php_data->{$section}->{$key} // '';
                        if ( $value =~ m/^\-?\d+$/ ) {
                            $php_ini .= sprintf "%-40s = %d\n", $key, $value;
                        }
                        else {
                            $php_ini .= sprintf "%-40s = \"%s\"\n", $key, $value;
                        }
                    }
                }
                my $php_ini_path = File::Spec->catfile( $to_user_homedir, 'php.ini' );
                Cpanel::FileUtils::Write::overwrite( $php_ini_path, $php_ini, 0644 );

                return;
            },
            $to_user_uid,
            $to_user_gid
        );
    }
    catch {
        $self->add_warning( 'Failed to save PHP INI for the domain: ' . Cpanel::Exception::get_string_no_id($_) );
    };
    return 1;
}

sub _parse_phpinfo {
    my $self = shift;

    my $data;
    foreach my $key ( keys %{ $self->{'phpinfo'} } ) {
        if ( $key =~ m/\./ ) {
            my ( $section, $real_key ) = split /\./, $key, 2;
            $data->{$section}->{$real_key} = $self->{'phpinfo'}->{$key};
        }
        else {
            $data->{'PHP'}->{$key} = $self->{'phpinfo'}->{$key};
        }
    }
    return $data;
}

sub _populate_phpinfo {
    my ( $self, $opts_hr ) = @_;
    return 1 if $self->{'phpinfo'};

    my $success = 0;
    try {
        # Dies if no PHP packages are installed, and short-circuits the
        # PHP version check early on.
        my $php = Cpanel::ProgLang->new( type => 'php' );
        undef $php;

        my ( $from_user_uid, $from_user_gid ) = ( Cpanel::PwCache::getpwnam( $self->{'from_username'} ) )[ 2, 3 ];
        my $resp;
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                my $temp_obj  = Cpanel::TempFile->new( { 'path' => $opts_hr->{'docroot'}, 'suffix' => 'php' } );
                my $temp_file = $temp_obj->file();

                Cpanel::FileUtils::Write::overwrite( $temp_file, _phpinfo_code(), 0644 );

                my $filename = File::Basename::basename($temp_file);
                my $ua       = Cpanel::HTTP::Client::SpecifyHost->new()->die_on_http_error();

                # What if they have a 'always redirect to ssl', etc setup?
                $ua->set_default_header( "Host", $opts_hr->{'domain'} );
                $resp = $ua->get( 'http://' . $opts_hr->{'ip'} . '/' . $filename );
            },
            $from_user_uid,
            $from_user_gid
        );

        # UA dies on any HTTP error, so if we get here,
        # $resp->success is a given, and $resp->content
        # will be populated.
        $self->{'phpinfo'} = Cpanel::JSON::Load( $resp->content );
        $success = 1;
    }
    catch {
        $self->add_warning( 'Failed to fetch PHP info for the domain: ' . Cpanel::Exception::get_string_no_id($_) );
    };

    return $success;
}

sub _validate_required_params {
    my ( $operation, $opts_hr ) = @_;

    if ( !( $opts_hr && 'HASH' eq ref $opts_hr ) ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] detailing the data migration' );    ## no extract maketext (developer error message. no need to translate)
    }

    my $required_params = {
        'fetch_php_version_for_domain' => [qw(domain docroot ip)],
        'set_php_version_for_domain'   => [qw(domain phpversion)],
    };
    die Cpanel::Exception::create( 'InvalidParameter', 'Unknown operation specified: [_1]', [$operation] )    ## no extract maketext (developer error message. no need to translate)
      if !exists $required_params->{$operation};

    my @exceptions;
    foreach my $required_arg ( @{ $required_params->{$operation} } ) {
        if ( not defined $opts_hr->{$required_arg} ) {
            push @exceptions, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_arg] );
        }
    }

    die Cpanel::Exception::create( 'Collection', 'Missing required parameters', [], { exceptions => \@exceptions } ) if scalar @exceptions;
    return 1;
}

sub _phpinfo_code {
    return <<'END_OF_PHP';
<?php
// We dont really care about the "global" vs "local" values here,
// so we set 'DETAILS=false' in this call to get just the settings
// that are in effect. This also normalizes the data structure
// we get back.
$a = ini_get_all(null, false);
$v = phpversion();
$a['php_version'] = $v;
echo json_encode($a);
?>
END_OF_PHP
}

1;

{
    # HTTP::Tiny explicitly prevents us from specifying the
    # 'Host' header.
    #
    # This subclass of Cpanel::HTTP::Client allows us to
    # bypass that restriction, and lets us to query domains
    # on the local server, without having to worry about whether the
    # domain is 'live' or not.
    package Cpanel::HTTP::Client::SpecifyHost;

    use parent qw(Cpanel::HTTP::Client);

    our $VERSION = '1.0';

    sub _prepare_headers_and_cb {
        my ( $self, $request, $args, $url, $auth ) = @_;

        my ( $host_header, $was_default_header );
        for (qw(default_headers headers)) {
            next unless $self->{$_};
            foreach my $k ( keys %{ $self->{$_} } ) {
                if ( lc $k eq 'host' ) {
                    $host_header        = $self->{$_}->{$k};
                    $was_default_header = 1 if $_ eq 'default_headers';
                    delete $self->{$_}->{$k};
                }
            }
        }
        $self->SUPER::_prepare_headers_and_cb( $request, $args, $url, $auth );
        $request->{headers}{'host'}        = $host_header if $host_header;
        $self->{'default_headers'}{'host'} = $host_header if $was_default_header;
        return;
    }

    1;

}
