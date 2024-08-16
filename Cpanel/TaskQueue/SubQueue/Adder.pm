package Cpanel::TaskQueue::SubQueue::Adder;

# cpanel - Cpanel/TaskQueue/SubQueue/Adder.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskQueue::SubQueue::Adder

=head1 SYNOPSIS

    {
        package My::SubQueue::Adder;

        use parent qw( Cpanel::TaskQueue::SubQueue::Adder );
    }

    My::SubQueue::Adder->add('new_entry');

=head1 DESCRIPTION

This is a base class for L<Cpanel::TaskQueue> subqueue “adder” modules.
Subclass this
when you want a module that can add items to the harvest queue.

See L<Cpanel::TaskQueue::SubQueue> for more information on subqueues
and their uses. See L<Cpanel::TaskQueue::SubQueue::Harvester>
for the “harvester” logic.

=cut

use parent qw( Cpanel::TaskQueue::SubQueue );

use Try::Tiny;

use Cpanel::Exception        ();
use Cpanel::Fcntl::Constants ();

use constant {
    _ENOENT => 2,
    _EEXIST => 17,

    _MAX_TRIES_TO_CREATE_TEMP => 5,
};

=head1 SUBCLASS INTERFACE

=over

=item * C<_DIR()> - Required. It is suggested to define this in a
base class that your L<Cpanel::TaskQueue::SubQueue::Harvester> subclass
can also subclass.

=item * C<_DIR_MODE()> - Optional; defaults to 0700.

=back

=cut

use constant _DIR_MODE => 0700;

=head1 METHODS

=head2 $new_yn = I<CLASS>->add( NAME [, CONTENT] )

Adds an item to the queue. If the C<_DIR()> doesn’t exist, this function
will create it with the C<_DIR_MODE()> that you’ve specified.

B<NOTE:> If you want to pre-validate the NAME, do that in an override
method in your subclass, then call this parent method once you’ve validated.

NAME cannot begin with a period (C<.>); otherwise there are no general
restrictions.

If CONTENT is given, then that value is serialized and stored as the queue
item’s contents. See L<Cpanel::TaskQueue::SubQueue::Harvester> for how
to use this value while harvesting.

This returns 1 if the entry was actually created or 0 if the entry
already existed.

=cut

sub add {
    my ( $self, $name, $content ) = @_;

    die "Invalid name: “$name”" if index( $name, '.' ) == 0;

    if ( length $content ) {
        return $self->_add_content( $name, $content );
    }

    my $path = $self->_DIR() . "/$name";

    return $self->_create_file_with_mkdir_fallback($path) ? 1 : 0;
}

sub _create_file_with_mkdir_fallback {
    my ( $self, $path ) = @_;

    my $tried_once;

    my $fhmode = $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL;

    local $!;

    my $fh;

    {
        sysopen( $fh, $path, $fhmode ) or do {
            return undef if $! == _EEXIST();

            if ( !$tried_once && $! == _ENOENT() ) {
                $tried_once = 1;
                $self->_ensure_file_parent_directory($path);
                redo;
            }

            die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $path, error => $!, mode => $fhmode ] );
        };
    }

    return $fh;
}

sub _ensure_file_parent_directory {
    my ( $self, $file_path ) = @_;

    my $dir = substr( $file_path, 0, rindex( $file_path, '/' ) );

    require Cpanel::Mkdir;
    Cpanel::Mkdir::ensure_directory_existence_and_mode(
        $dir,
        $self->_DIR_MODE(),
    );

    return;
}

sub _add_content {
    my ( $self, $name, $content ) = @_;

    require Cpanel::JSON;
    require Cpanel::FileUtils::Write;
    $content = Cpanel::JSON::Dump($content);

    my $fh;

    my $wrote;

    my $content_pfx = $self->_CONTENT_PREFIX();
    my $path        = $self->_DIR() . "/$content_pfx$name";

    for ( 1, 2 ) {
        try {
            $wrote = Cpanel::FileUtils::Write::write( $path, $content );
        }
        catch {
            my $is_ok;

            if ( try { $_->isa('Cpanel::Exception::IO::FileCreateError') } ) {

                #The directory probably doesn’t exist. Add it, then retry.
                if ( $_->error_name() eq 'ENOENT' ) {
                    $self->_ensure_file_parent_directory($path);
                    $is_ok = 1;
                }

                #The entry already exists, so there’s nothing to do.
                elsif ( $_->error_name() eq 'EEXIST' ) {
                    $wrote = 0;
                    $is_ok = 1;
                }
            }

            if ( !$is_ok ) {
                local $@ = $_;
                die;
            }
        };

        last if defined $wrote;
    }

    return $wrote;
}

1;
