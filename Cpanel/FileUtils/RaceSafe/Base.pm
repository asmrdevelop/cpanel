package Cpanel::FileUtils::RaceSafe::Base;

# cpanel - Cpanel/FileUtils/RaceSafe/Base.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::RaceSafe::Base - Race-safe datastore initialization

=head1 SYNOPSIS

    package SomeSubclass;

    use parent qw( Cpanel::FileUtils::RaceSafe::Base );

    sub _create_file {
        my ($self, %opts) = @_;

        #Create the file at $self->{'_tmp_path'} ..
    }

    package main;

    use SomeSubclass;

    my $safe_obj = SomeSubclass->new( path => '..', .. );

    #...then, after initializing the datastore:

    $safe_obj->install();   #if you want any and all errors to throw

    $safe_obj->install_unless_exists();     #won't throw if error is EEXIST

    $safe_obj->force_install();     #replace anything that EEXISTs

=head1 DESCRIPTION

This base class was intended to solve a problem wherein there
are three possible race statuses for setting up a datastore:

=over 4

=item 1. the file does not exist

=item 2. the file exists, but the schema is not yet set up

=item 3. the file exists, and the schema is set up

=back

We can eliminate state #2 by creating a temp file, setting up the datastore
in that file, then just C<link()>ing from the new path to the temp path.
That C<link()> can still fail, of course, but in that case it’s probably ok
because we can assume that the file that occupies the new path has a schema.

(Of course, if anything creates the DB without using this method, then all
bets are off!)

This base class implements the described behavior generically so that
the same method could be used with flat files or any other filesystem-based
storage format.

See L<Cpanel::FileUtils::RaceSafe::SQLite> for a reference implementation.

=cut

#----------------------------------------------------------------------

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Autodie   ();
use Cpanel::Exception ();

my $FORCE_INSTALL_MAX_TRIES = 10;

#----------------------------------------------------------------------
#opts:
#
#   path - the eventual path of the file
#
sub new {
    my ( $class, %opts ) = @_;

    my $temp_file = join( '.', $opts{'path'}, 'creating', scalar(localtime), $$, rand );

    my $self = {
        _path         => $opts{'path'},
        _tmp_path     => $temp_file,
        _original_pid => $$,
    };
    bless $self, $class;

    $self->_create_file( $temp_file, %opts );

    return $self;
}

sub DESTROY {
    my ($self) = @_;

    if ( $$ == $self->{'_original_pid'} ) {
        Cpanel::Autodie::unlink_if_exists( $self->{'_tmp_path'} );
    }

    return;
}

#----------------------------------------------------------------------
#NOTE: Override this for subclasses. It receives arguments:
#
#   - the temp file
#   - the %opts key/value pairs passed into new()
#
sub _create_file { die 'ABSTRACT' }

#----------------------------------------------------------------------

#This won't die() if there is already something sitting in this file's
#intended path. (That seems the most generally useful behavior?)
#
#Returns 1 or 0 to indicate whether it made any change or not.
#
sub install_unless_exists {
    my ($self) = @_;

    my $ret;

    try {
        $ret = $self->install();
    }
    catch {
        die $_ if !try { $_->isa('Cpanel::Exception::IO::LinkError') };
        die $_ if $_->error_name() ne 'EEXIST';
    };

    return $ret || 0;
}

#Are you sure you don’t want install_unless_exists()?
#
sub install {
    my ($self) = @_;

    return Cpanel::Autodie::link( @{$self}{qw( _tmp_path  _path )} );
}

#for testing
our $_todo_cr_before_each_force_install_attempt;

#Try, and keep trying, to install. unlink() the file on EEXIST failures;
#rethrow anything else.
#
sub force_install {
    my ($self) = @_;

    my $ret;

    my $it_worked;

    for ( 1 .. $FORCE_INSTALL_MAX_TRIES ) {
        if ($_todo_cr_before_each_force_install_attempt) {

            # for testing
            $_todo_cr_before_each_force_install_attempt->();
        }

        try {
            $ret       = $self->install();
            $it_worked = 1;
        }
        catch {
            die $_ if !try { $_->isa('Cpanel::Exception::IO::LinkError') };
            die $_ if $_->error_name() ne 'EEXIST';

            # This will always be a Cpanel::Exception::IO::LinkError
            Cpanel::Autodie::unlink_if_exists( $_->get('newpath') );
        };

        return $ret if $it_worked;
    }

    #NOTE: This should never happen in production. Knock on wood.
    die Cpanel::Exception->create( 'The system tried [quant,_1,time,times] to create a filesystem link from “[_2]” to “[_3]”, but each time “[_2]” already existed, even though the system [asis,unlink()]ed that file on each attempt.', [ $FORCE_INSTALL_MAX_TRIES, @{$self}{qw( _path  _tmp_path )} ] );
}

1;
