package Cpanel::SSLCerts;

# cpanel - Cpanel/SSLCerts.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module is for service SSL certificates besides Apache, i.e., where
# the entire service only has the one certificate.
#----------------------------------------------------------------------

require 5.014;    # for s///r
use strict;
use warnings;
use Cwd                           ();
use Cpanel::DAV::Provider         ();
use Cpanel::OS                    ();
use Cpanel::Logger                ();
use Cpanel::LoadFile              ();
use Cpanel::SSL::Verify           ();
use Cpanel::PwCache               ();
use Cpanel::FileUtils::Access     ();
use Cpanel::FileUtils::TouchFile  ();
use Cpanel::FileUtils::Write      ();
use Cpanel::LoadModule            ();
use Cpanel::Server::Type          ();
use Cpanel::SafeDir::MK           ();
use Cpanel::TempFile              ();
use Cpanel::Sys::Hostname         ();
use Cpanel::SSL::Create           ();
use Cpanel::SSL::DefaultKey::User ();
use Cpanel::SSL::Utils            ();
use Cpanel::Validate::Domain      ();
use Cpanel::StringFunc::Trim      ();
use Cpanel::Exception             ();
use Cpanel::SV                    ();

our $VERSION = '1.6';

our $base_cpanel_ssl_dir = '/var/cpanel/ssl';

## PEM/.pem: Privacy Enhanced Mail

## see bin/checkallsslcerts: set to 1
our $allow_cert_cache = 0;

my %CERT_CACHE;
my $SEC_IN_DAY = 86400;

## TODO: rename $rSSLC variables to something readable that doesn't sound like a sneeze
## TODO?: not clear what generates the '^my' service files

## IMPORTANT: if a key is added, mirror the key in &Cpanel::SSL::ServiceMap.
our $rSERVICES;

sub rSERVICES {
    return $rSERVICES //= {
        'dovecot' => {
            'has_domains' => 1,                                   # If the certificate has domain on it
            'description' => 'Dovecot Mail Server',
            'owner'       => [ 'root', Cpanel::OS::sudoers() ],
            'dir'         => 'dovecot',
            'dnsonly'     => 1,
            'grouptype'   => 'default',
            'symlinkdirs' => ['/etc/dovecot/ssl'],

            'required_service_names' => [ 'pop', 'imap' ],
            'default_filelist'       => [
                {
                    'symlink'  => 'dovecot.key',
                    'file'     => 'dovecot.key',
                    'contents' => ['key']
                },
                {
                    'symlink'  => 'dovecot.crt',
                    'file'     => 'dovecot.crt',
                    'contents' => ['crt']
                }
            ],
            'configured_filelist' => [
                {
                    'symlink'  => 'dovecot.crt',
                    'file'     => 'mydovecot.crt',
                    'contents' => [ 'crt', 'cab' ]
                },
                {
                    'symlink'  => 'dovecot.key',
                    'file'     => 'mydovecot.key',
                    'contents' => ['key']
                }
            ],
        },
        ## FIXME?: ftp is the only one whose configured_filelist->file does not have a '^my' filename
        ## note: related to case 44177
        'ftp' => {
            'has_domains'            => 1,                                   # If the certificate has domain on it
            'description'            => 'FTP Server',
            'owner'                  => [ 'root', Cpanel::OS::sudoers() ],
            'dir'                    => 'ftp',
            'grouptype'              => 'default',
            'symlinkdirs'            => [ '/etc', '/etc/ssl/private' ],
            'required_service_names' => ['ftpd'],
            'default_filelist'       => [
                {
                    'symlink'  => 'pure-ftpd.pem',
                    'file'     => 'pure-ftpd.pem',
                    'contents' => [ 'key', 'crt', 'cab' ]
                },
                {
                    'symlink'  => 'ftpd-ca.pem',
                    'file'     => 'ftpd-ca.pem',
                    'contents' => ['cab'],
                },
                {
                    'symlink'  => 'ftpd-rsa-key.pem',
                    'file'     => 'ftpd-rsa-key.pem',
                    'contents' => ['key']
                },
                {
                    'symlink'  => 'ftpd-rsa.pem',
                    'file'     => 'ftpd-rsa.pem',
                    'contents' => ['crt']
                }
            ],
            'configured_filelist' => [
                {
                    'symlink'  => 'pure-ftpd.pem',
                    'file'     => 'pure-ftpd.pem',
                    'contents' => [ 'key', 'crt', 'cab' ]
                },
                {
                    'symlink'  => 'ftpd-rsa-key.pem',
                    'file'     => 'myftpd-rsa-key.pem',
                    'contents' => ['key']
                },
                {
                    'symlink'  => 'ftpd-rsa.pem',
                    'file'     => 'myftpd-rsa.pem',
                    'contents' => [ 'crt', 'cab' ]
                }
            ],
        },

        'mail_apns' => {
            'has_domains'            => 0,                                   # If the certificate has domain on it
            'description'            => 'iOS Push for Mail',
            'owner'                  => [ 'root', Cpanel::OS::sudoers() ],
            'dir'                    => 'mail_apns',
            'verify'                 => \&_verify_mail_apns_certificate,
            'grouptype'              => 'ios_mail',
            'required_service_names' => ['imap'],
            'default_filelist'       => [
                {
                    'symlink'  => 'key.pem',
                    'file'     => 'key.pem',
                    'contents' => ['key']
                },
                {
                    'symlink'  => 'cert.pem',
                    'file'     => 'cert.pem',
                    'contents' => ['crt']
                }
            ],
            'configured_filelist' => [
                {
                    'symlink'  => 'key.pem',
                    'file'     => 'key.pem',
                    'contents' => ['key']
                },
                {
                    'symlink'  => 'cert.pem',
                    'file'     => 'cert.pem',
                    'contents' => ['crt']
                }
            ],
        },

        'exim' => {
            'has_domains'            => 1,                        # If the certificate has domain on it
            'description'            => 'Exim (SMTP) Server',
            'owner'                  => [ 'mailnull', 'mail' ],
            'dir'                    => 'exim',
            'dnsonly'                => 1,
            'grouptype'              => 'default',
            'symlinkdirs'            => ['/etc'],
            'required_service_names' => ['exim'],
            'default_filelist'       => [
                {
                    'symlink'  => 'exim.key',
                    'file'     => 'exim.key',
                    'contents' => ['key']
                },
                {
                    'symlink'  => 'exim.crt',
                    'file'     => 'exim.crt',
                    'contents' => ['crt']
                }
            ],
            'configured_filelist' => [
                {
                    'symlink'  => 'exim.key',
                    'file'     => 'myexim.key',
                    'contents' => ['key']
                },
                {
                    'symlink'  => 'exim.crt',
                    'file'     => 'myexim.crt',
                    'contents' => [ 'crt', 'cab' ]
                }
            ],
        },
        'cpanel' => {
            'has_domains'               => 1,                                                        # If the certificate has domain on it
            'defaults_hides_configured' => 1,
            'description'               => 'Calendar, cPanel, WebDisk, Webmail, and WHM Services',
            'owner'                     => [ 'cpanel', 'cpanel' ],
            'dnsonly'                   => 1,
            'grouptype'                 => 'default',
            'dir'                       => 'cpanel',
            'required_service_names'    => ['cpsrvd'],
            'default_filelist'          => [
                {
                    'file'     => 'cpanel.pem',
                    'contents' => [ 'key', 'crt' ]
                }
            ],
            'configured_filelist' => [
                {
                    'file'     => 'mycpanel.pem',
                    'contents' => [ 'key', 'crt', 'cab' ]
                },
                {
                    'file'     => 'mycpanel.cabundle',
                    'contents' => ['cab']
                }
            ],
        }
    };
}

my $caldav_apns = {
    'has_domains'            => 0,
    'description'            => 'iOS Push for CalDAV',
    'owner'                  => [ 'root', 'cpanel-ccs' ],
    'dir'                    => 'caldav_apns',
    'verify'                 => \&_verify_calendar_apns_certificate,
    'grouptype'              => 'ios_mail',
    'required_service_names' => ['cpanel-ccs'],
    'default_filelist'       => [
        {
            'symlink'  => 'key.pem',
            'file'     => 'key.pem',
            'contents' => ['key']
        },
        {
            'symlink'  => 'cert.pem',
            'file'     => 'cert.pem',
            'contents' => ['crt']
        }
    ],
    'configured_filelist' => [
        {
            'symlink'  => 'key.pem',
            'file'     => 'key.pem',
            'contents' => ['key']
        },
        {
            'symlink'  => 'cert.pem',
            'file'     => 'cert.pem',
            'contents' => ['crt']
        }
    ],
};
my $carddav_apns = {
    'has_domains'            => 0,
    'description'            => 'iOS Push for CardDAV',
    'owner'                  => [ 'root', 'cpanel-ccs' ],
    'dir'                    => 'carddav_apns',
    'verify'                 => \&_verify_contacts_apns_certificate,
    'grouptype'              => 'ios_mail',
    'required_service_names' => ['cpanel-ccs'],
    'default_filelist'       => [
        {
            'symlink'  => 'key.pem',
            'file'     => 'key.pem',
            'contents' => ['key']
        },
        {
            'symlink'  => 'cert.pem',
            'file'     => 'cert.pem',
            'contents' => ['crt']
        }
    ],
    'configured_filelist' => [
        {
            'symlink'  => 'key.pem',
            'file'     => 'key.pem',
            'contents' => ['key']
        },
        {
            'symlink'  => 'cert.pem',
            'file'     => 'cert.pem',
            'contents' => ['crt']
        }
    ],

};

sub getSSLServiceList {
    if ( !exists( rSERVICES()->{'caldav_apns'} ) && -f Cpanel::DAV::Provider::OVERRIDE_FILE() ) {
        $rSERVICES->{'caldav_apns'}  = $caldav_apns;
        $rSERVICES->{'carddav_apns'} = $carddav_apns;
    }
    return $rSERVICES;
}

#Pass in a list of domains for the cert.
sub _generateGenericPEM {

    my $key_type = Cpanel::SSL::DefaultKey::User::get('root');
    my $keygen   = Cpanel::SSL::Create::key($key_type);

    my $tfile = Cpanel::TempFile->new();
    my ( $keyfile, $key_fh ) = $tfile->file();

    print {$key_fh} $keygen or return ( 0, "The system failed to write to $keyfile: $!" );
    close $key_fh           or return ( 0, "The system failed to close $keyfile: $!" );

    my $hostname = Cpanel::Sys::Hostname::gethostname();

    require Cpanel::OpenSSL;
    my $openssl = Cpanel::OpenSSL->new();

    my $certgen = $openssl->generate_cert(
        {
            keyfile      => $keyfile,
            domains      => [$hostname],
            emailAddress => "ssl\@$hostname",
        }
    );
    return ( 0, $certgen->{'message'} || $certgen->{'stderr'} ) if !$certgen->{'status'};

    return (
        1,
        {
            crt => $certgen->{'stdout'},
            key => $keygen,
        }
    );
}

## checks for expired certs, potentially recreating default ones, and returns an array-ref of service names
sub checkForExpiredServiceCrts {
    my $skip_create = shift;
    my $days        = shift || 3;

    my $service_data_ref = _get_service_data();
    my @EXPLIST;
    foreach my $service ( available_services() ) {
        my $default_filelist = $service_data_ref->{$service}->{'default_filelist'};
        foreach my $hr_service_file_descr ( @{$default_filelist} ) {
            my $hr_describes_certfile = grep { $_ eq 'crt' } @{ $hr_service_file_descr->{'contents'} };
            if ($hr_describes_certfile) {
                my $ssldir        = _get_dir_for_service($service);
                my $cert_to_check = _get_cert_fullpath( $ssldir, $hr_service_file_descr );

                if ( checkExpired( $cert_to_check, $days ) ) {
                    push( @EXPLIST, $service );

                    ## FIXME?: can this be done elsewhere, so this function does one thing?
                    ##   see checkallsslcerts: it is already doing this. so why a $skip_create?
                    if ( !$skip_create ) {
                        createDefaultSSLFiles( 'service' => $service );
                    }
                }
                ## cert file processed; keep looping through default_filelist, as 'ftp' in specific
                ##   has two cert files to check
            }
        }
    }
    return \@EXPLIST;
}

## the '^my' cert file has precedence
## FIXME (case 44177): this is naively prepending "my"; it should use 'configured_filelist' for the case
##   of FTP above, which does not prepend
## FIXME (case 44177): move similar usage of 'configured_filelist' to this function
sub _get_cert_fullpath {
    my ( $ssldir, $hr_service_file_descr ) = @_;
    my $cert_to_check = "$ssldir/my" . $hr_service_file_descr->{'file'};
    unless ( -f $cert_to_check ) {
        $cert_to_check = "$ssldir/" . $hr_service_file_descr->{'file'};
    }
    return $cert_to_check;
}

## checks equality on a cert's Subject and Issuer
sub checkSelfSigned {
    my $cert_path = shift;

    if ( my $crt_text = Cpanel::LoadFile::loadfile($cert_path) ) {
        my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_certificate_text($crt_text);
        return if !$ok;

        return $parse->{'is_self_signed'};
    }
    else {
        return 1;    # if we cannot load it we consider it self signed
    }

    return;
}

## checks $cert's text for "Not After", comparing with current time
sub checkExpired {
    my ( $cert_path, $days ) = @_;

    $days ||= 3;

    if ( my $cert_text = Cpanel::LoadFile::loadfile($cert_path) ) {

        my ( $status, $not_after ) = get_expire_time($cert_text);

        if ( !$status || ( $not_after - ( $SEC_IN_DAY * $days ) ) < current_unix_time() ) {
            return 1;
        }

    }
    else {
        return 1;    # if we cannot load it we consider it expired
    }
    return 0;
}

## time() for testing purposes
sub current_unix_time {
    return time();
}

#
# returns when the certificate will expire
# accepts cert text
#
sub get_expire_time {
    my ($cert_text) = @_;

    return ( 0, 0 ) if !$cert_text;

    my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_certificate_text($cert_text);
    return ( 0, $parse ) if !$ok;

    return ( 1, $parse->{'not_after'} );
}

## for $service: ensures dir structure, moves '^my' cert files out of way, generates generic cert and
##   outputs to filename given in data structure above, sets permissions, handles symlinks, and
##   outputs -CN file
*resetSSLFiles = *createDefaultSSLFiles;

sub createDefaultSSLFiles {
    my %OPTS               = @_;
    my $skip_nonselfsigned = 0;

    if ( exists $OPTS{'skip_nonselfsigned'} ) {
        $skip_nonselfsigned = $OPTS{'skip_nonselfsigned'};
    }

    my ( $service_ok, $service ) = _get_service_from_opts( \%OPTS );
    if ( !$service_ok ) { return wantarray ? ( 0, $service ) : 0; }

    my ( $dir_create_status, $dir_create_statusmsg ) = _create_ssl_dirs($service);
    return ( $dir_create_status, $dir_create_statusmsg ) if $dir_create_status;

    # Move away the old certificates we are replacing, but keep a backup
    ## namely, the '^my" service files
    my $now                 = time();
    my $ssldir              = _get_dir_for_service($service);
    my $service_data_ref    = _get_service_data();
    my $configured_filelist = $service_data_ref->{$service}->{'configured_filelist'};

    if ($skip_nonselfsigned) {
        foreach my $cfile ( @{$configured_filelist} ) {
            if ( $cfile->{'contents'} && grep { $_ eq 'crt' } @{ $cfile->{'contents'} } ) {
                return ( 0, "Not a Self Signed Cert" ) if !checkSelfSigned( "$ssldir/" . $cfile->{'file'} );
            }
        }
    }

    # Case 156785, generate new cert before disabling old one.

    my ( $ok, $rSSLOBJS ) = _generateGenericPEM();
    return ( 0, $rSSLOBJS ) if !$ok;

    my $needs_apache_rebuild = 0;
    foreach my $cfile ( @{$configured_filelist} ) {
        my $rename = "$ssldir/" . $cfile->{'file'};
        if ( rename $rename, "$rename.disable.$now" ) {
            $needs_apache_rebuild = 1;
        }
    }

    my $message;
    my $failed = 0;

    my $default_filelist = $service_data_ref->{$service}->{'default_filelist'};
    ## output 'default_filelist'->'file' with $rSSLOBJS values as keyed by the service's contents array
    foreach my $cfile ( @{$default_filelist} ) {
        my $target_file = $ssldir . '/' . $cfile->{'file'};
        $message .= "Saving cert to $target_file\n";
        my $contents = join '', map { "$_\n" }
          map { $rSSLOBJS->{$_} =~ s/\s+$//gr }
          grep { defined $rSSLOBJS->{$_} } @{ $cfile->{contents} };
        if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( $target_file, $contents, 0660 ) ) {
            $failed = 1;
            $message .= "Failed to create default SSL file $target_file\n";
            _logger()->warn("Failed to create default SSL file $target_file: $!");
            if ( -e "$target_file.disable.$now" ) {    # try to restore the previous one if it failed
                rename "$target_file.disable.$now", $target_file;
            }
        }
    }

    _setsslperms();
    generateSymLinks( $service, 'default' );
    saveCNName( 'service' => $service );
    saveCRTInfo( 'service' => $service );
    if ($needs_apache_rebuild) {
        require Cpanel::HttpUtils::ApRestart::BgSafe;
        Cpanel::HttpUtils::ApRestart::BgSafe::rebuild();
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();
    }
    return wantarray ? ( 1, "<pre>$message Default SSL files created\n</pre>" ) : 1;
}

# Symlink the location the location service looks for the certificate to
# where the certificate actually is
#
# service: the name os the service
# configtype: default or configured (configured is for non self signed)

## for $service, creates the array of 'symlinkdirs' in the given $configtype '_filelist'
sub generateSymLinks {
    my ( $service, $configtype ) = @_;

    my $service_data_ref = _get_service_data();
    if ( !$service ) {
        return ( 0, "You must provide a service" );
    }
    if ( !exists $service_data_ref->{$service} ) {
        return ( 0, "“$service” is not a known service" );
    }

    ## note: $configtype is one of 'default' or 'configured'

    my $ssldir   = _get_dir_for_service($service);
    my $filelist = $service_data_ref->{$service}->{ $configtype . '_filelist' };
    foreach my $cfile ( @{$filelist} ) {
        foreach my $symlinkdir ( @{ $service_data_ref->{$service}->{'symlinkdirs'} } ) {
            if ( !-e $symlinkdir ) {
                Cpanel::SafeDir::MK::safemkdir( $symlinkdir, '0755' );
            }
            my $destination = "$ssldir/" . $cfile->{'file'};
            my $the_symlink = "$symlinkdir/" . $cfile->{'symlink'};

            my $link_dest = _readlink_if_exists($the_symlink);

            if ( $link_dest ne $destination ) {
                unlink($the_symlink);
                symlink( $destination, $the_symlink ) or warn "symlink($destination, $the_symlink): $!";
            }
        }
    }
    return 1;
}

sub installSSLFiles {
    my %OPTS = @_;
    my ( $service_ok, $service ) = _get_service_from_opts( \%OPTS );
    if ( !$service_ok ) { return wantarray ? ( 0, $service ) : 0; }

    my ( $dir_create_status, $dir_create_statusmsg ) = _create_ssl_dirs($service);
    return ( $dir_create_status, $dir_create_statusmsg ) if $dir_create_status;

    Cpanel::LoadModule::load_perl_module('Cpanel::SSLInfo');
    $OPTS{'crt'} = Cpanel::SSLInfo::demunge_ssldata( $OPTS{'crt'} );
    $OPTS{'key'} = Cpanel::SSLInfo::demunge_ssldata( $OPTS{'key'} );
    $OPTS{'cab'} = Cpanel::SSLInfo::demunge_ssldata( $OPTS{'cab'} );

    my ( $cert_ok, $cert_hr ) = Cpanel::SSL::Utils::parse_certificate_text( $OPTS{'crt'} );
    if ( !$cert_ok ) {
        return ( 0, "Invalid certificate: $cert_hr" );
    }

    my ( $key_ok, $key_hr ) = Cpanel::SSL::Utils::parse_key_text( $OPTS{'key'} );
    if ( !$key_ok ) {
        return ( 0, "Invalid key: $key_hr" );
    }

    my ( $status, $result );
    my $service_data_ref = _get_service_data();
    if ( $service_data_ref->{$service}{'verify'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::OrDie');
        ( $status, $result ) = Cpanel::OrDie::convert_die_to_multi_return( sub { $service_data_ref->{$service}{'verify'}->( $OPTS{'crt'}, $OPTS{'key'}, $OPTS{'cab'}, $OPTS{'quiet'} ) } );
    }
    else {
        ( $status, $result ) = Cpanel::SSLInfo::verifysslcert( undef, $OPTS{'crt'}, $OPTS{'key'}, $OPTS{'cab'}, $OPTS{'quiet'}, 1 );
    }
    if ( $status != 1 ) {
        return ( 0, $result );
    }

    if ( $OPTS{'cab'} ) {

        # FB Case 87489:  Calling the "reverse" version because that will order the
        # Certificates from "lowest" (issuer of the cert) to "highest" (issued by root)
        # so the whole certificate chain will be in order (cert, issuer ... root)
        my ( $status, $cab ) = Cpanel::SSL::Utils::normalize_cabundle_order( $OPTS{'cab'} );
        return ( $status, $cab ) if !$status;
        $OPTS{'cab'} = $cab;
    }

    my $ssldir     = _get_dir_for_service($service);
    my $configtype = 'configured';
    my $filelist   = $service_data_ref->{$service}->{ $configtype . '_filelist' };
    foreach my $cfile ( @{$filelist} ) {
        my $contents = '';
        foreach my $sslobj ( @{ $cfile->{'contents'} } ) {
            if ( $OPTS{$sslobj} && $OPTS{$sslobj} =~ /----/ ) {
                $OPTS{$sslobj} =~ s/\s+$//g;
                $contents .= $OPTS{$sslobj} . "\n";
            }
        }

        next if ( !length $contents && scalar @{ $cfile->{'contents'} } == 1 && $cfile->{'contents'}->[0] eq 'cab' );    # cab is optional

        my $target_file = $ssldir . '/' . $cfile->{'file'};
        if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( $target_file, $contents, 0660 ) ) {
            return ( 0, "Failed to write $target_file" );
        }
    }
    _setsslperms();
    generateSymLinks( $service, 'configured' );
    if ( service_has_domains($service) ) {
        saveCNName( 'service' => $service );
        saveCRTInfo( 'service' => $service );
    }
    return ( 1, 'Install Complete' );
}

## case 38517: removed &get_common_name_from_crt_txt (formerly known as &getCNNameFromCRTTXT)

## returns text version of cert, potentially from package scoped cache
sub cached_get_cert_text {
    my ( $openssl, $cert_fname ) = @_;
    if ( $allow_cert_cache && exists $CERT_CACHE{$cert_fname} ) {
        return $CERT_CACHE{$cert_fname};
    }
    $CERT_CACHE{$cert_fname} = $openssl->get_cert_text( { 'crtfile' => $cert_fname } );

    # If no stdout or stderr, then OpenSSL execution failed and the crt was not checked
    if ( !exists $CERT_CACHE{$cert_fname}->{'stdout'} && !exists $CERT_CACHE{$cert_fname}->{'stderr'} ) {
        _logger()->warn("openssl execution failed when checking $cert_fname");
        delete $CERT_CACHE{$cert_fname};
        return;
    }
    return $CERT_CACHE{$cert_fname};
}

## FIXME!: does not handle multi-line values
## outputs -CRTINFO for service, based on the service SSL files
## note: -CRTINFO files are used by Cpanel::Redirect; only current use
sub saveCRTInfo {
    my %OPTS = @_;
    my ( $service_ok, $service ) = _get_service_from_opts( \%OPTS );
    if ( !$service_ok ) { return wantarray ? ( 0, $service ) : 0; }

    my $rSSLC = fetchSSLFiles( 'service' => $service );
    require Cpanel::OpenSSL;
    my $openssl = Cpanel::OpenSSL->new();
    my $ssl_res = $openssl->get_cert_text( { 'stdin' => $rSSLC->{'crt'} } );
    my $ssldir  = _get_dir_for_service($service);
    if ( !$ssl_res->{'text'} ) {
        _logger()->warn("Failed to parse certificate passed to saveCRTInfo");
        unlink "$ssldir-CRTINFO";
        return 0;
    }

    my %CRTKEYS;
    foreach my $line ( split( /\n/, $ssl_res->{'text'} ) ) {
        my ( $key, $value ) = split( /:/, $line, 2 );
        next if !defined $key;
        $key   =~ s/\s+/ /g;
        $key   =~ s/^\s*|\s*$//g;
        $value =~ s/^\s*|\s*$//g if defined $value;
        $CRTKEYS{$key} = $value;
    }

    if (
        !Cpanel::FileUtils::Write::overwrite_no_exceptions(
            "$ssldir-CRTINFO",
            join(
                "\n",
                map { $_ . ': ' . ( $CRTKEYS{$_} || '' ) } keys %CRTKEYS
              )
              . "\n",
            0644
        )
    ) {

        _logger()->warn("Failed to write $ssldir-CRTINFO: $!");
        unlink "$ssldir-CRTINFO";
        return 0;
    }

    my ( $status, $not_after ) = get_expire_time( $rSSLC->{'crt'} );

    if ( !$status ) {
        _logger()->warn("Failed to get_expire_time in saveCRTINFO");
        return 0;
    }

    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( "$ssldir-NOT_AFTER", $not_after, 0644 ) ) {
        _logger()->warn("Failed to write $ssldir-NOT_AFTER: $!");
        unlink "$ssldir-NOT_AFTER";
        return 0;
    }

    return 1;
}

## prints $domain common name (CN) from $service SSL file into its -CN file
sub saveCNName {
    my %OPTS = @_;
    my ( $service_ok, $service ) = _get_service_from_opts( \%OPTS );
    if ( !$service_ok ) { return wantarray ? ( 0, $service ) : 0; }

    my $rSSLC = fetchSSLFiles( 'service' => $service );

    my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_certificate_text( $rSSLC->{'crt'} );
    if ( !$ok ) {
        my $cert_text = $rSSLC->{'crt'} || '';
        warn "Failed to parse “$cert_text”: $parse";
        return 0;
    }

    my $domain = $parse->{'domains'}->[0];

    # Cpanel::SSL::Utils::validate_cabundle_for_certificate not use here since
    # we want to validate that its signed by a root CA we trust as well
    my $ssl_verify = Cpanel::SSL::Verify->new();
    my $crt_verify = $ssl_verify->verify( $rSSLC->{'crt'}, $rSSLC->{'cab'} || () );

    #XXX TODO: Shouldn’t there be some response here if $crt_verify indicates an error?

    my $ssldir = _get_dir_for_service($service);

    if ( $domain && Cpanel::Validate::Domain::validwildcarddomain($domain) ) {
        if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( "$ssldir-CN", $domain, 0644 ) ) {
            _logger()->warn("Failed to write $ssldir-CN: $!");
            unlink "$ssldir-CN";
            return 0;
        }
        if (
            !Cpanel::FileUtils::Write::overwrite_no_exceptions(
                "$ssldir-DOMAINS",
                join(
                    "\n",
                    map {
                        my $s = $_;
                        $s =~ s/\n//g;
                        $s;
                    } @{ $parse->{'domains'} }
                ),
                0644
            )
        ) {
            _logger()->warn("Failed to write $ssldir-DOMAINS: $!");
            unlink "$ssldir-DOMAINS";
            return 0;
        }
    }
    else {
        _logger()->warn("The primary domain “$domain” on certificate that is currently installed for “$service” is not valid.");
        unlink( "$ssldir-CN", "$ssldir-DOMAINS" );
        return 0;
    }

    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( "$ssldir-SIGNATURE_CHAIN_VERIFIED", ( $crt_verify->ok() ? 1 : 0 ), 0644 ) ) {
        _logger()->warn("Failed to write $ssldir-SIGNATURE_CHAIN_VERIFIED: $!");
        unlink "$ssldir-SIGNATURE_CHAIN_VERIFIED";
        return 0;
    }

    return 1;
}

#Inputs:
#
#   - service (required)
#
#   - configtype (optional, ???)
#
#Returns a hashref of:
#
#   - crt   (PEM)
#   - cab   (PEM, newline-joined)
#   - key   (PEM)
#
sub fetchSSLFiles {
    my %OPTS = @_;
    my ( $service_ok, $service ) = _get_service_from_opts( \%OPTS );
    if ( !$service_ok ) { die $service; }
    my $service_data_ref = _get_service_data();

    my $needconfig = $OPTS{'configtype'};
    my $configtype;

    my $ssldir = _get_dir_for_service($service);
    if ($needconfig) {
        $configtype = $needconfig;
    }
    else {
        $configtype = _get_service_config_type($service);
    }
    my @keyfiles;
    my @crtfiles;
    my $filelist = $service_data_ref->{$service}->{ $configtype . '_filelist' };
    my %HAS_FOUND_SSL_ITEM;

  SSL_FILES_TO_CHECK:
    foreach my $cfile ( @{$filelist} ) {
        my $file_on_disk = $ssldir . '/' . $cfile->{'file'};
        next if !-e $file_on_disk;

        foreach my $item ( @{ $cfile->{'contents'} } ) {
            next SSL_FILES_TO_CHECK if $HAS_FOUND_SSL_ITEM{$item};    # Do not use duplicate items
                                                                      # If we do not skip cabundles
                                                                      # we have already found, multiple
                                                                      # ones will get glued together
            $HAS_FOUND_SSL_ITEM{$item} = 1;
        }

        if ( grep { $_ eq 'key' } @{ $cfile->{'contents'} } ) {
            unshift( @keyfiles, $file_on_disk );
        }
        elsif ( grep { $_ eq 'crt' } @{ $cfile->{'contents'} } ) {

            # CRT files come first
            unshift( @crtfiles, $file_on_disk );
        }
        elsif ( grep { $_ eq 'cab' } @{ $cfile->{'contents'} } ) {

            # CABs always need to go at the end
            push( @crtfiles, $file_on_disk );
        }
    }

    my $verified_path = "$base_cpanel_ssl_dir/$service-SIGNATURE_CHAIN_VERIFIED";
    my $verified      = Cpanel::LoadFile::loadfile($verified_path);
    chomp $verified if defined $verified;

    my @fileorder = ( @keyfiles, @crtfiles );
    my $ssldata   = deparsesslfiles( \@fileorder );
    return undef unless $ssldata;
    $ssldata->{'certificate_file'} = $crtfiles[0] || $keyfiles[0];
    $ssldata->{'verified'}         = $verified ? 1 : 0;
    return $ssldata;
}

sub deparsesslfiles {

    #ALWAYS GIVE KEY FIRST AND THE MAIN CERTIFICATE FILE LAST
    my $rFILES = shift;

    my %SSL_OBJECTS;

    my $currenttype;
    foreach my $pem_file ( @{$rFILES} ) {
        if ( my $pem_text = Cpanel::LoadFile::loadfile($pem_file) ) {
            while ( $pem_text =~ m/(\-+BEGIN[^\-]+\-+)(.*?)(\-+END[^\-]+\-+)/sig ) {
                my $typeline   = $1;
                my $currentbuf = "$1$2$3";
                Cpanel::StringFunc::Trim::ws_trim( \$currentbuf );

                if ( $typeline =~ m/KEY/ ) {
                    $currenttype = 'key';
                }
                elsif ( $typeline =~ m/CERTIFICATE/ ) {
                    $currenttype = 'crt';
                }
                else {
                    $currenttype = 'unknown';
                }
                push( @{ $SSL_OBJECTS{$currenttype} }, Cpanel::StringFunc::Trim::ws_trim($currentbuf) );
            }
        }
    }

    my %SSLDATA;

    # The first certificate is always "THE" certificate
    $SSLDATA{'crt'} = shift( @{ $SSL_OBJECTS{'crt'} } );

    # The next certificates are always the cabundle
    $SSLDATA{'cab'} = join( "\n", @{ $SSL_OBJECTS{'crt'} } );

    # The first key is the ONLY key
    $SSLDATA{'key'} = shift( @{ $SSL_OBJECTS{'key'} } );

    return \%SSLDATA;
}

sub check_service_ssl_dirs {
    if ( !-e $base_cpanel_ssl_dir ) {
        Cpanel::SafeDir::MK::safemkdir( $base_cpanel_ssl_dir, '0755' );
    }
    elsif ( !-d _ ) {
        _logger()->warn("cPanel SSL certificate storage directory $base_cpanel_ssl_dir does not exist");
    }

    my $service_data_ref = _get_service_data();
    foreach my $service ( keys %{$service_data_ref} ) {
        my $ssldir = _get_dir_for_service($service);
        if ( !-e $ssldir ) {
            Cpanel::SafeDir::MK::safemkdir( $ssldir, '0700' );
        }
        if ( !-d $ssldir ) {
            _logger()->warn("cPanel SSL certificate storage directory $ssldir does not exist");
        }
    }
    return;
}

## TODO: comment
sub _setsslperms {
    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Dir');
    my $service_data_ref = _get_service_data();
    foreach my $service ( keys %{$service_data_ref} ) {
        my $check_dir = _get_dir_for_service($service);
        next if !-e $check_dir;

        foreach my $node ( @{ Cpanel::FileUtils::Dir::get_directory_nodes($check_dir) } ) {
            my $modfile = Cpanel::SV::untaint("$check_dir/$node");
            next if index( $modfile, '.disable.' ) > -1;

            #If a pw/gr lookup fails, we set the account to root since the service likely isn't installed
            $service_data_ref->{$service}->{'owner_uid'} //= ( Cpanel::PwCache::getpwnam( ${ $service_data_ref->{$service}->{'owner'} }[0] ) )[2] || 0;
            $service_data_ref->{$service}->{'owner_gid'} //= ( getgrnam( ${ $service_data_ref->{$service}->{'owner'} }[1] ) )[2]                  || 0;

            Cpanel::FileUtils::Access::ensure_mode_and_owner( $modfile, 0660, $service_data_ref->{$service}->{'owner_uid'}, $service_data_ref->{$service}->{'owner_gid'} );
        }
        chmod( 0755, $check_dir );
    }
    return;
}

sub getCurrentCrtInfo {
    my %OPTS = @_;
    my ( $service_ok, $service ) = _get_service_from_opts( \%OPTS );
    if ( !$service_ok ) { return wantarray ? ( 0, $service ) : 0; }

    my $rSSLC = fetchSSLFiles( 'service' => $service );
    require Cpanel::OpenSSL;
    my $openssl = Cpanel::OpenSSL->new();
    my $ssl_res = $openssl->get_cert_text( { 'stdin' => $rSSLC->{'crt'} } );
    return if !$ssl_res->{'text'};
    return join( "\n", grep( /^\s*(Subject\s*:\s*|Issuer\s*:\s*|Not\s*Before\s*:|Not\s*After\s*:)/i, split( /\n/, $ssl_res->{'text'} ) ) );
}

sub migrateCerts {
    check_service_ssl_dirs();

    Cpanel::FileUtils::TouchFile::touchfile( $base_cpanel_ssl_dir . '/active' );
    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Copy');

    foreach my $sslobj ( 'ftpd-rsa-key.pem', 'ftpd-rsa.pem' ) {
        if ( -e "/etc/$sslobj" && !-e $base_cpanel_ssl_dir . '/ftp/' . $sslobj ) {
            Cpanel::FileUtils::Copy::safecopy( "/etc/$sslobj", $base_cpanel_ssl_dir . '/ftp/' . $sslobj );
            chmod( 0660, $base_cpanel_ssl_dir . '/ftp/' . $sslobj );
            if ( -e $base_cpanel_ssl_dir . '/ftp/' . $sslobj ) {
                unlink("/etc/$sslobj");
                symlink( $base_cpanel_ssl_dir . '/ftp/' . $sslobj, "/etc/$sslobj" );
            }
        }
    }

    foreach my $sslobj ( 'exim.key', 'exim.crt' ) {
        if ( -e "/etc/$sslobj" && !-e $base_cpanel_ssl_dir . '/exim/' . $sslobj ) {
            Cpanel::FileUtils::Copy::safecopy( "/etc/$sslobj", $base_cpanel_ssl_dir . '/exim/' . $sslobj );
            chmod( 0660, $base_cpanel_ssl_dir . '/exim/' . $sslobj );
            if ( -e $base_cpanel_ssl_dir . '/exim/' . $sslobj ) {
                unlink("/etc/$sslobj");
                symlink( $base_cpanel_ssl_dir . '/exim/' . $sslobj, "/etc/$sslobj" );
            }
        }
    }

    foreach my $pem ( 'mycpanel.pem', 'mycpanel.cabundle', 'cpanel.pem' ) {
        if (  !-l "/usr/local/cpanel/etc/$pem"
            && -e "/usr/local/cpanel/etc/$pem"
            && !-e $base_cpanel_ssl_dir . '/cpanel/' . $pem ) {
            Cpanel::FileUtils::Copy::safecopy( "/usr/local/cpanel/etc/$pem", $base_cpanel_ssl_dir . '/cpanel/' . $pem );
            chmod( 0660, $base_cpanel_ssl_dir . '/cpanel/' . $pem );
            if ( -e $base_cpanel_ssl_dir . '/cpanel/' . $pem ) {
                unlink("/usr/local/cpanel/etc/$pem");
            }
        }
    }

    return _setsslperms();
}

*checkperms = *_setsslperms;

## returns array of service names, based on $service_data_ref filtered with consistency checks
sub available_services {
    my $dnsonly = Cpanel::Server::Type::is_dnsonly();
    my @services;
    my $service_data_ref = _get_service_data();
    foreach my $service ( keys %{$service_data_ref} ) {
        next if ( !$service_data_ref->{$service}{'dnsonly'} && $dnsonly );
        next if !_any_service_is_enabled( $service_data_ref->{$service}{'required_service_names'} );
        push @services, $service;
    }

    return @services;
}

sub _any_service_is_enabled {
    my ($services_ar) = @_;

    require Cpanel::Services::Enabled;
    foreach my $service (@$services_ar) {
        return 1 if Cpanel::Services::Enabled::is_enabled($service);
    }

    return 0;
}

sub check_symlinks {
    my $service_data_ref = _get_service_data();
    foreach my $service ( available_services() ) {
        next if !service_has_domains($service) || !$service_data_ref->{$service}{'symlinkdirs'};
        generateSymLinks( $service, _get_service_config_type($service) );
    }
    return;
}

sub _create_ssl_dirs {
    my $service = shift;

    if ( !-e $base_cpanel_ssl_dir ) {
        mkdir $base_cpanel_ssl_dir, 0755;
    }

    my $ssldir;
    my $service_data_ref = _get_service_data();
    if ( $service_data_ref->{$service}->{'dir'} ) {
        $ssldir = _get_dir_for_service($service);
        if ( !-e $ssldir ) {
            mkdir $ssldir, 0755;
        }
        elsif ( !-d $ssldir ) {
            _logger()->warn("Archiving item $ssldir to ${ssldir}.back");
            rename $ssldir, $ssldir . '.back';
            mkdir $ssldir, 0755;
        }

        if ( !-d $ssldir ) {
            _logger()->warn("Failed to create directory $ssldir");
            return wantarray ? ( 0, 'System error. Unable to create SSL directory.' ) : 0;
        }
    }
    else {
        _logger()->warn('No service directory specified');
        return wantarray ? ( 0, 'No service directory specified' ) : 0;
    }
}

sub service_has_domains {
    my ($service) = @_;
    my $service_data_ref = _get_service_data();
    return $service_data_ref->{$service}{'has_domains'} ? 1 : 0;
}

sub update_cert_info_files {
    foreach my $service ( available_services() ) {
        next if !service_has_domains($service);
        my @check_files = ( 'CN', 'SIGNATURE_CHAIN_VERIFIED', 'DOMAINS' );
        my @need_updated_files =
          grep { !-e "$base_cpanel_ssl_dir/$service-$_" || ( ( stat("$base_cpanel_ssl_dir/$service-$_") )[2] & 07777 ) != 0644 } @check_files;
        if (@need_updated_files) {
            saveCNName( 'service' => $service ) || warn "Failed to analyze certificate for service: $service";
        }
        @check_files = ( 'CRTINFO', 'NOT_AFTER' );
        @need_updated_files =
          grep { !-e "$base_cpanel_ssl_dir/$service-$_" || ( ( stat("$base_cpanel_ssl_dir/$service-$_") )[2] & 07777 ) != 0644 } @check_files;
        if (@need_updated_files) {
            saveCRTInfo( 'service' => $service ) || warn "Failed to analyze certificate for service: $service";
        }
    }
    return 1;
}

my $logger;

sub _logger {
    return ( $logger ||= Cpanel::Logger->new() );
}

sub __verify_apns_certificate {
    my ( $cert_text, $key_text, $userId ) = @_;

    $userId ||= 'com.apple.mail';

    Cpanel::LoadModule::load_perl_module('Cpanel::SSL::Utils');
    my ( $c_ok, $c_parse ) = Cpanel::SSL::Utils::parse_certificate_text($cert_text);

    if ( !$c_ok ) {
        die Cpanel::Exception->create_raw("This certificate cannot be parsed ($c_parse). It may be corrupt or in an unrecognized format.");
    }
    my $crt_modulus = $c_parse->{'modulus'};

    my ( $k_ok, $k_parse ) = Cpanel::SSL::Utils::parse_key_text($key_text);
    if ( !$k_ok ) {
        die Cpanel::Exception->create_raw('This key cannot be parsed. It may be corrupt or in an unrecognized format.');
    }
    my $key_modulus = $k_parse->{'modulus'};

    if ( $crt_modulus ne $key_modulus ) {
        die Cpanel::Exception->create_raw("The certificate modulus [$crt_modulus] does not match the key modulus [$key_modulus].");
    }
    elsif ( $c_parse->{'issuer'}{'organizationName'} !~ m{apple}i ) {
        die Cpanel::Exception->create_raw("The certificate must be issued by Apple.");
    }
    elsif ( !$c_parse->{'subject'}{'userId'} ) {
        die Cpanel::Exception->create_raw("The certificate is missing the userId field (0.9.2342.19200300.100.1.1)");
    }
    elsif ( index( $c_parse->{'subject'}{'userId'}, $userId ) != 0 ) {
        die Cpanel::Exception->create_raw("The certificate userId field (0.9.2342.19200300.100.1.1) must begin with “$userId.”");
    }
    return 1;
}

sub _verify_mail_apns_certificate {
    my $userId = 'com.apple.mail';
    return __verify_apns_certificate( $_[0], $_[1], $userId );
}

sub _verify_calendar_apns_certificate {
    my $userId = 'com.apple.calendar';
    return __verify_apns_certificate( $_[0], $_[1], $userId );
}

sub _verify_contacts_apns_certificate {
    my $userId = 'com.apple.contact';
    return __verify_apns_certificate( $_[0], $_[1], $userId );
}

sub _get_service_from_opts {
    my ($opts_ref) = @_;

    my $service          = $opts_ref->{'service'};
    my $service_data_ref = _get_service_data();
    if ( !$service ) {
        _logger()->warn('No service provided.');
        return ( 0, 'You must provide a service.' );
    }
    elsif ( !exists $service_data_ref->{$service} ) {
        my $valid_services = join( ',', sort keys %$service_data_ref );
        _logger()->warn("“$service” is not a known service.");
        return ( 0, "“$service” is not a known service. It must be one of “$valid_services”." );
    }
    return ( 1, $service );
}

# No idea why this was defined twice here previously...
# Aliasing it now so that I don't have to update tests
*_get_service_data = \&getSSLServiceList;

sub _get_service_config_type {
    my ($service) = @_;

    my $service_data_ref      = _get_service_data();
    my $ssldir                = _get_dir_for_service($service);
    my $first_configured_file = ${ $service_data_ref->{$service}->{'configured_filelist'} }[0]->{'file'};
    if ( $service_data_ref->{$service}->{'defaults_hides_configured'} ) {
        if ( -e "$ssldir/$first_configured_file" ) {
            return 'configured';
        }
    }
    else {
        my @configured_only_files_for_service = _get_files_for_service_that_are_configured_only($service);

        foreach my $configured_file_that_is_not_default_file (@configured_only_files_for_service) {
            if ( -e $configured_file_that_is_not_default_file ) {
                return 'configured';
            }
        }

        if ( !@configured_only_files_for_service ) {

            # If they are the same we have to check symlinks
            my $first_configured_symlink = ${ $service_data_ref->{$service}->{'configured_filelist'} }[0]->{'symlink'};
            foreach my $symlinkdir ( @{ $service_data_ref->{$service}->{'symlinkdirs'} } ) {
                my $link_dest = _readlink_if_exists("$symlinkdir/$first_configured_symlink");

                if ( $link_dest eq "$ssldir/$first_configured_file" && -e "$ssldir/$first_configured_file" ) {
                    return 'configured';
                }
            }
        }

    }

    return 'default';
}

sub _readlink_if_exists {
    my ($path) = @_;

    return $path if !-l $path;
    return readlink($path) // do {
        warn "readlink($path): $!" if !$!{'ENOENT'};
        q<>;
    };
}

sub _get_files_for_service_that_are_configured_only {
    my ($service) = @_;

    my $service_data_ref = _get_service_data();
    my $ssldir           = _get_dir_for_service($service);

    # If any of the configured files that are not default files exists, its configured
    my %configured_files = ( map { ( "$ssldir/$_->{'file'}" => 1 ) } @{ $service_data_ref->{$service}->{'configured_filelist'} } );
    my %default_files    = ( map { ( "$ssldir/$_->{'file'}" => 1 ) } @{ $service_data_ref->{$service}->{'default_filelist'} } );

    delete @configured_files{ keys %default_files };

    return keys %configured_files;
}

sub _get_dir_for_service {
    my ($service) = @_;
    my $service_data_ref = _get_service_data();

    if ( !exists $service_data_ref->{$service} ) {
        die "“$service” is not a known service";
    }
    return "$base_cpanel_ssl_dir/" . $service_data_ref->{$service}->{'dir'};
}

1;
