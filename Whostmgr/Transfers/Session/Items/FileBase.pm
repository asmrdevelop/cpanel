package Whostmgr::Transfers::Session::Items::FileBase;

# cpanel - Whostmgr/Transfers/Session/Items/FileBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Whostmgr::Transfers::Session::Item';

our $VERSION = '1.0';

use Cpanel::FileUtils::Write ();
use Cpanel::Encoder::Tiny    ();

sub transfer {
    my ($self) = @_;

    return $self->exec_path(
        [
            qw(_transfer_init
              _create_target_dir_if_needed
              create_remote_object
              _transfer_file),
            ( $self->can('post_transfer') ? 'post_transfer' : () )
        ]
    );
}

# No post transfer prep needed by default
sub restore {
    my ($self) = @_;

    return $self->success();

}

sub _create_target_dir_if_needed {
    my ($self) = @_;

    my $dir = $self->module_info()->{'dir'};
    $self->set_percentage(25);

    if ( -d $dir ) {
        return ( 1, 'OK' );
    }
    elsif ( mkdir( $dir, $self->module_info()->{'perms'} ) ) {
        return ( 1, 'Created directory' );
    }
    else {
        return ( 0, $self->_locale()->maketext( "Failed to create the directory: “[_1]”.", $dir ) );
    }
}

sub _transfer_init {
    my ($self) = @_;

    $self->session_obj_init();

    foreach my $required_object (qw(session_obj output_obj authinfo remote_info)) {
        if ( !defined $self->{$required_object} ) {
            return ( 0, $self->_locale()->maketext( "“[_1]” failed to create “[_2]”.", ( caller(0) )[3], $required_object ) );
        }
    }

    return ( 1, "All required objects loaded" );
}

sub _transfer_file {
    my ($self) = @_;

    my $path = $self->module_info()->{'dir'} . '/' . $self->item();
    $self->{'output_obj'}->set_source( { 'host' => $self->{'remote_info'}->{'sshhost'} } );
    my ( $cat_ok, $result ) = $self->{'remoteobj'}->cat_file($path);
    $self->{'output_obj'}->set_source();
    $self->set_percentage(50);

    if ( !$cat_ok ) {
        return ( 0, $result );
    }
    elsif ( !length $result ) {
        return ( 0, $self->_locale()->maketext( "Unable to download “[_1]”: [_2]", Cpanel::Encoder::Tiny::safe_html_encode_str( $self->item_name() ), Cpanel::Encoder::Tiny::safe_html_encode_str( $self->item() ) ) );
    }
    else {
        $self->set_percentage(75);
        if ( Cpanel::FileUtils::Write::overwrite_no_exceptions( $path, $result, 0644 ) ) {
            print $self->_locale()->maketext( "Transferred “[_1]” ([_2]) OK.", Cpanel::Encoder::Tiny::safe_html_encode_str( $self->item_name() ), Cpanel::Encoder::Tiny::safe_html_encode_str( $self->item() ) ) . "\n";
        }
        else {
            return ( 0, $self->_locale()->maketext( "The system failed to write the file “[_1]” because of an error: [_2]", $path, "$!" ) );
        }
    }

    return ( 1, 'Transfered' );

}

1;
