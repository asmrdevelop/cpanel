package Cpanel::SmallConstCache;

# cpanel - Cpanel/SmallConstCache.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::SafeDir::MK                  ();
use Cpanel::FileUtils::Write             ();
use Cpanel::Exception                    ();
use Cpanel::Validate::FilesystemNodeName ();

my $MAX_VALUE_SIZE = 1024;

###########################################################################
#
# Method:
#   new
#
# Description:
#   This module provides a simple filesystem cache for key value
#   pairs when the value is between 0 and $MAX_VALUE_SIZE.
#
# Parameters:
#   dir - The directory to store the cache in
#
# Exceptions:
#   MissingParameter - provided when the dir parameter is missing.
#   IO::DirectoryCreateError - provided if the directory that stores the cache cannot be created.
#
# Returns:
#   A Cpanel::SmallConstCache object
#
sub new {
    my ( $class, %OPTS ) = @_;

    my $dir = $OPTS{'dir'};

    die Cpanel::Exception::create( 'MissingParameter', 'The required parameter “[_1]” is not set.', ['dir'] ) if !$dir;

    my $self = bless { 'dir' => $dir }, $class;

    if ( !-e $dir ) {
        Cpanel::SafeDir::MK::safemkdir( $dir, 0700 ) || die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $dir, error => $! ] );
    }

    return $self;
}

sub fetch {
    my ( $self, $key ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($key);

    return ( stat("$self->{'dir'}/$key") )[7];
}

sub add {
    my ( $self, $key, $value ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($key);

    die Cpanel::Exception->create_raw("add requires a value between 0 and $MAX_VALUE_SIZE") if $value !~ m{^[0-9]+} || $value < 0 || $value > $MAX_VALUE_SIZE;

    return Cpanel::FileUtils::Write::overwrite_no_exceptions( "$self->{'dir'}/$key", "1" x $value, 0600 );
}

sub expire {
    my ( $self, $key ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($key);

    return unlink("$self->{'dir'}/$key");
}

sub expire_all {
    my ($self) = @_;

    opendir( my $dh, $self->{'dir'} ) or do {
        die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $self->{'dir'}, error => $! ] );
    };

    while ( my $key = readdir($dh) ) {
        next if $key =~ m{^[.]{1,2}$};

        unlink("$self->{'dir'}/$key") || warn "Failed to remove “$self->{'dir'}/$key”: $!.";
    }

    return 1;
}

1;
