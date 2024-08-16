package Whostmgr::Transfers::ConvertAddon::MigrateData::DirPath;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/DirPath.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData);

use Cpanel::Exception ();

sub copy_dirpath {
    my ( $self, $opts_hr ) = @_;

    $self->ensure_users_exist();

    if ( !( $opts_hr && 'HASH' eq ref $opts_hr ) ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] detailing the data migration' );    ## no extract maketext (developer error message. no need to translate)
    }

    _validate_required_params($opts_hr);

    if ( -d $opts_hr->{'from_dir'} ) {
        $self->safesync_dirs( { 'source_dir' => $opts_hr->{'from_dir'}, 'target_dir' => $opts_hr->{'to_dir'} } );
    }

    return 1;
}

# Note: this does not validate whether
# the directories exist or not.
# That is left up to the caller.
sub _validate_required_params {
    my $opts = shift;

    my @exceptions;
    foreach my $required_arg (qw(from_dir to_dir)) {
        if ( not defined $opts->{$required_arg} ) {
            push @exceptions, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_arg] );
        }
    }

    die Cpanel::Exception::create( 'Collection', 'Invalid or Missing required parameters', [], { exceptions => \@exceptions } ) if scalar @exceptions;
    return 1;
}

1;
