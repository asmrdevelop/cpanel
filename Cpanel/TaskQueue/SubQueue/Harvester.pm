package Cpanel::TaskQueue::SubQueue::Harvester;

# cpanel - Cpanel/TaskQueue/SubQueue/Harvester.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskQueue::SubQueue::Harvester

=head1 SYNOPSIS

    {
        package My::SubQueue::Harvester;

        use parent qw( Cpanel::TaskQueue::SubQueue::Harvester );
    }

    my $names_ar = My::SubQueue::Harvester->harvest();

    #alternatively …
    My::SubQueue::Harvester->harvest( sub {
        my ($name, $contents) = @_;
    } );

=head1 DESCRIPTION

This is a base class for TaskQueue subqueue “harvester” modules. Subclass
this when you want a module that can read items from the harvest queue.

See L<Cpanel::TaskQueue::SubQueue> for more information on subqueues
and their uses. See L<Cpanel::TaskQueue::SubQueue::Adder>
for the “adder” logic.

=cut

use parent qw( Cpanel::TaskQueue::SubQueue );

use Try::Tiny;

use Cpanel::Exception  ();
use Cpanel::Finally    ();
use Cpanel::LoadModule ();

use constant _ENOENT => 2;

=head1 SUBCLASS INTERFACE

=over

=item * C<_DIR()> - Required. It is suggested to define this in a
base class that your L<Cpanel::TaskQueue::SubQueue::Harvester> subclass
can also subclass.

=back

=head1 METHODS

=head2 I<CLASS>->harvest( CALLBACK )

Removes all items from the queue and calls CALLBACK immediately before
removing each one. The CALLBACK receives the name of the just-removed
item and, if the item has any CONTENT, that value. Nothing is returned.

(NB: C<harvest()> works with a callback to avoid “forgetting” entries
if, e.g., there is a power failure between the harvest of the queue and
completion of processing the names.)

The queue items are processed and returned in lexicographical order.

=cut

sub harvest {
    my ( $self, $foreach_cr ) = @_;

    my $dir = $self->_DIR();

    local $!;

    if ( opendir my $dh, $dir ) {
        my @names = readdir($dh);
        die "readdir($dir): $!" if $!;

        #Sort lexically so there is at least a defined order of iteration.
        @names = sort @names;

        while (@names) {
            my $name = shift @names;

            my $has_content = ( index( $name, $self->_CONTENT_PREFIX() ) == 0 );

            #skip anything that starts with “.” that we don’t recognize.
            next if !$has_content && ( index( $name, '.' ) == 0 );

            my $processing_path = "$dir/.processing.$$.$name";

            rename( "$dir/$name" => $processing_path ) or do {
                warn "rename($dir/$name): $!" if $! != _ENOENT();
                next;
            };

            my $unlink_at_end = Cpanel::Finally->new(
                sub {
                    unlink $processing_path or do {
                        warn "unlink($processing_path): $!";
                    };
                }
            );

            try {
                if ($has_content) {
                    Cpanel::LoadModule::load_perl_module('Cpanel::LoadFile');
                    Cpanel::LoadModule::load_perl_module('Cpanel::JSON');

                    my $payload = Cpanel::LoadFile::load($processing_path);

                    $foreach_cr->(
                        substr( $name, length $self->_CONTENT_PREFIX() ),
                        Cpanel::JSON::Load($payload),
                    );
                }
                else {
                    $foreach_cr->($name);
                }
            }
            catch {
                my $class = ref $self;
                warn "$class: Failed to process subqueue item “$name” from “$dir” because of an error: $_";
            };
        }
    }
    else {
        _handle_opendir_err($dir);
    }

    return;
}

=head2 I<CLASS>->has_content()

Returns a boolean that indicates whether there is content in the
datastore. This does not mutate the datastore.

=cut

sub has_content {
    my ($self) = @_;

    my $dir = $self->_DIR();

    local $!;

    if ( opendir my $dh, $dir ) {
        while ( my $name = readdir($dh) ) {
            next if index( $name, '.' ) == 0;

            return 1;
        }

        if ($!) {
            die "readdir($dir): $!";
        }
    }
    else {
        _handle_opendir_err($dir);
    }

    return 0;
}

#----------------------------------------------------------------------

sub _handle_opendir_err {
    my ($dir) = @_;

    if ( $! != _ENOENT() ) {
        die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $dir, error => $! ] );
    }

    return;
}

1;
