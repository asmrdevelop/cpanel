package Cpanel::HttpUtils::ApRestart::Defer;

# cpanel - Cpanel/HttpUtils/ApRestart/Defer.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeFile ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

our $DEFER_OBJECT_ACTIVE = 0;

=head1 NAME

Cpanel::HttpUtils::ApRestart::Defer - Defers backgrounded restarts

=head1 SYNOPSIS

    my $obj = Cpanel::HttpUtils::ApRestart::Defer->new();
    $obj->block_restarts;
    ... do some things that are unsafe to do when apache could restart at any momemt
    $obj->allow_restarts

or, if using the lexical constructor flag:

   my $obj = Cpanel::HttpUtils::ApRestart::Defer->new( 'lexical' => 1 );
   $obj->block_restarts;
   ... do unsafe things
   return; # this should remove the lock file when the object falls out of scope

=head1 DESCRIPTION

The purpose of this module is to provide a manner to consistently interact with the lock file for deferring apache restarts.

This will not lock out restarts for longer than the Cpanel::SafeFile timeout.

As of v68, we also maintain a lock on the httpd.conf to ensure that the following
functions block until the defer block is removed:

Cpanel::HttpUtils::ApRestart::forced_restart();
Cpanel::HttpUtils::ApRestart::safeaprestart();

=head1 METHODS

=head2 is_deferred()

static method, determines if apache restarts should be deferred or not.

=cut

sub is_deferred {
    return Cpanel::SafeFile::is_locked( _file_to_lock() );
}

=head2 new( [ lexical => 1 ] )

Instantiate the object.

Accepts the 'lexical' parameter which is used to remove the lock file if the object falls out of scope.

=cut

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = {};

    $self->{'_lexical'} = 1 if $OPTS{'lexical'};

    bless $self, $class;
    return $self;
}

=head2 block_restarts()

This method will lock a file that will defer all apache restarts.

=cut

sub block_restarts {
    my ($self) = @_;

    if ( !$self->{'restarts_blocked_by_this_object'} && $DEFER_OBJECT_ACTIVE ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess( "Implementor error: only one " . __PACKAGE__ . " may be active" );
    }

    $DEFER_OBJECT_ACTIVE = 1;

    if ( !$self->{'restarts_blocked_by_this_object'} ) {
        $self->{'httplock'}                        = Cpanel::SafeFile::safeopen( $self->{'http_conf_fh'}, '<', _file_to_lock() );
        $self->{'restarts_blocked_by_this_object'} = 1;

        if ( !$self->{'httplock'} ) {
            require Cpanel::Carp;
            die Cpanel::Carp::safe_longmess( "Failed to lock: " . _file_to_lock() );
        }

    }
    return 1;
}

=head2 allow_restarts()

This method will remove the lock file that defers all apache restarts.

=cut

sub allow_restarts {
    my ($self) = @_;

    if ( $self->{'httplock'} ) {
        Cpanel::SafeFile::safeclose( $self->{'http_conf_fh'}, $self->{'httplock'} );

        delete $self->{'httplock'};
        delete $self->{'http_conf_fh'};
    }

    $DEFER_OBJECT_ACTIVE = 0;
    $self->{'restarts_blocked_by_this_object'} = 0;
    return 1;
}

sub _file_to_lock {    ## for testing
    return apache_paths_facade->file_conf();
}

sub DESTROY {
    my ($self) = @_;
    $self->allow_restarts() if $self->{'_lexical'};
    return;
}

1;
