package Whostmgr::API::1::SSH;

# cpanel - Whostmgr/API/1/SSH.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                       ();
use Cpanel::Exception            ();
use Cpanel::Form::Param          ();
use Cpanel::Locale               ();
use Cpanel::SSH::Remote          ();
use Cpanel::SSH::CredentialCheck ();

use constant NEEDS_ROLE => {
    authorizesshkey               => undef,
    check_remote_ssh_connection   => undef,
    convertopensshtoputty         => undef,
    deletesshkey                  => undef,
    generatesshkeypair            => undef,
    importsshkey                  => undef,
    listsshkeys                   => undef,
    remote_basic_credential_check => undef,
};

use Try::Tiny;

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

*remote_basic_credential_check = \&Cpanel::SSH::CredentialCheck::remote_basic_credential_check;

sub check_remote_ssh_connection {
    my ( $args, $metadata ) = @_;

    my ( $host, $port ) = @{$args}{qw(host port)};
    my ( $resp, $err_obj );
    try {
        if ( !length $host ) {
            die Cpanel::Exception::create( 'MissingParameter', 'You must provide the “[_1]” argument.', ['host'] );
        }
        $resp = Cpanel::SSH::Remote::check_remote_ssh_connection( $host, $port );
    }
    catch {
        $err_obj = $_;
    };
    if ($err_obj) {
        @{$metadata}{qw(result reason)} = ( 0, Cpanel::Exception::get_string($err_obj) );
        return;
    }

    @{$metadata}{qw(result reason)} = qw( 1 OK );

    return $resp;
}

sub authorizesshkey {
    my ( $args, $metadata ) = @_;

    local $Cpanel::CPERROR{'ssh'};
    require Cpanel::SSH;
    my @result = Cpanel::SSH::_authkey( %{$args}, user => 'root' );

    $metadata->{'result'} = defined $result[1] ? 1    : 0;
    $metadata->{'reason'} = defined $result[1] ? 'OK' : ( $result[1] || $Cpanel::CPERROR{'ssh'} );

    return defined $result[0] ? { 'file' => $result[0], 'authorized' => $result[1] } : ();
}

sub deletesshkey {
    my ( $args, $metadata ) = @_;

    local $Cpanel::CPERROR{'ssh'};
    require Cpanel::SSH;
    my @result = Cpanel::SSH::_delkey( %{$args}, user => 'root' );

    $metadata->{'result'} = defined $result[0] ? 1    : 0;
    $metadata->{'reason'} = defined $result[0] ? 'OK' : ( $result[1] || $Cpanel::CPERROR{'ssh'} );

    return $result[0] ? { 'file' => $result[1], } : ();
}

sub generatesshkeypair {
    my ( $args, $metadata ) = @_;

    local $Cpanel::CPERROR{'ssh'};
    require Cpanel::SSH;
    my @result = Cpanel::SSH::_genkey( abort_on_existing_key => 1, %{$args}, user => 'root' );
    $metadata->{'result'} = $result[0] ? 1    : 0;
    $metadata->{'reason'} = $result[0] ? 'OK' : $Cpanel::CPERROR{'ssh'};

    if ( ref $result[1] && scalar @{ $result[1] } ) {
        $metadata->{'warnings'} = $result[1];
    }

    # These are the lines of text returned from ssh-keygen
    my @output_text = @{ $result[2] || [] };

    # Give the user a hint as to what might have failed.
    $metadata->{'output'}->{'raw'} = join( "\n", @output_text ) unless $metadata->{'result'};

    # No data returned from the function call
    unless ( scalar @output_text ) {
        return;
    }

    # for name we look for the beginning of the text line
    # for fingerprint we look to see if the line contains hex chars and colons

    my $name;
    my $fingerprint;

    foreach my $line (@output_text) {
        if ( $line =~ m|Your identification has been saved.+/([^/]+)\.| ) {
            $name = $1;
            next;
        }

        my $xline = $line;
        $xline =~ s/ //g;
        if ( $xline =~ m/^[0-9a-f:]+$/ ) {
            my $yline = $xline;
            my $cnt   = $yline =~ tr/://;

            # make sure the colons are there, to prevent false positives
            if ( $cnt > 5 ) {
                $fingerprint = $xline;
            }

            next;
        }
    }

    return {
        'name'        => $name,
        'fingerprint' => $fingerprint,
    };
}

sub importsshkey {
    my ( $args, $metadata ) = @_;

    local $Cpanel::CPERROR{'ssh'};

    require Cpanel::SSH;
    my ( $result, $warnings_ar ) = Cpanel::SSH::_importkey( %{$args}, user => 'root' );

    $metadata->{'result'} = $result ? 1 : 0;
    if ($result) {
        $metadata->{'reason'} = 'OK';
    }
    else {
        $metadata->{'reason'} = $Cpanel::CPERROR{'ssh'};
    }

    if ( $warnings_ar && scalar @{$warnings_ar} ) {
        $metadata->{'warnings'} = $warnings_ar;
    }

    return;
}

sub convertopensshtoputty {
    my ( $args, $metadata ) = @_;

    local $Cpanel::CPERROR{'ssh'};
    require Cpanel::SSH;
    my $ppk_text = Cpanel::SSH::_converttoppk( %{$args}, user => 'root' );
    $metadata->{'result'} = defined $ppk_text ? 1 : 0;
    if ($ppk_text) {
        $metadata->{'reason'} = 'OK';
        return { 'key' => $ppk_text, };
    }
    else {
        $metadata->{'reason'} = $Cpanel::CPERROR{'ssh'};
    }

    return;
}

sub listsshkeys {
    my ( $args, $metadata ) = @_;

    my $fixed_parseform = Cpanel::Form::Param->new( { 'parseform_hr' => $args } );
    $args->{'files'} = [ $fixed_parseform->param('files') ];

    local $Cpanel::CPERROR{'ssh'};
    require Cpanel::SSH;
    my ( $keys_ar, $warnings_ar ) = Cpanel::SSH::_listkeys( %{$args}, user => 'root' );

    # In the event that there are simply no keys yet, this call should not return an error, but an empty list
    my $success = $warnings_ar ? 1 : 0;

    $metadata->{'result'} = $success ? 1    : 0;
    $metadata->{'reason'} = $success ? 'OK' : $Cpanel::CPERROR{'ssh'};

    if ( $warnings_ar && scalar @{$warnings_ar} ) {
        $metadata->{'warnings'} = $warnings_ar;
    }

    return $success ? { 'keys' => $keys_ar } : ();
}

1;
