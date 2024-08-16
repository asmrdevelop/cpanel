package Cpanel::LogTailer;

# cpanel - Cpanel/LogTailer.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#----------------------------------------------------------------------
#This is a base class. Subclasses must provide:
#   methods:
#       new()
#       _dir()
#   attributes:
#       _renderer_obj
#----------------------------------------------------------------------

use Cpanel::Fcntl                        ();
use Cpanel::Exception                    ();
use Cpanel::LogTailer::Renderer::Generic ();
use Cpanel::FileUtils::Open              ();
use Cpanel::UTF8::Strict                 ();
use Cpanel::TimeHiRes                    ();
use Cpanel::Validate::FilesystemNodeName ();

#Returns the write-only filehandle.
#Note that this will only CREATE a file; it die()s otherwise.
sub _active_file {
    my ( $self, $file_name, $flags ) = @_;

    local $!;
    Cpanel::FileUtils::Open::sysopen_with_real_perms( my $log_fh, $self->_file_name_to_path_active($file_name), $flags, 0600 ) or do {
        die Cpanel::Exception::create(
            'IO::FileCreateError',
            [
                path        => $self->_file_name_to_path_active(),
                error       => $!,
                permissions => 0600,
            ]
        );
    };

    return $log_fh;
}

#Returns the write-only filehandle.
#Note that this will only CREATE a file; it die()s otherwise.
sub create_active_file {
    my ( $self, $file_name ) = @_;

    return $self->_active_file( $file_name, Cpanel::Fcntl::or_flags(qw( O_WRONLY O_TRUNC O_CREAT )) );
}

#Returns the write-only filehandle.
#Note that this will only APPEND a file; it die()s otherwise.
sub append_active_file {
    my ( $self, $file_name ) = @_;

    return $self->_active_file( $file_name, Cpanel::Fcntl::or_flags(qw( O_WRONLY O_APPEND )) );
}

sub is_log_completed {
    my ( $self, $file_name ) = @_;

    return -e $self->_file_name_to_path_completed($file_name) ? 1 : 0;
}

sub mark_log_completed {
    my ( $self, $file_name ) = @_;

    my $incomplete_file = $self->_file_name_to_path_active($file_name);
    my $complete_file   = $self->_file_name_to_path_completed($file_name);

    local $!;
    rename( $incomplete_file, $complete_file ) or do {
        die Cpanel::Exception::create( 'IO::RenameError', [ oldpath => $incomplete_file, newpath => $complete_file, error => $! ] );
    };

    return 1;
}

sub tail_log {
    my ( $self, $file_name, $position, $opts ) = @_;

    return $self->tail_logs( [ [ $file_name, $position ] ], $opts );
}

sub add_log_files {
    my ( $self, $files_ref ) = @_;

    local $!;
    foreach my $file_data ( @{$files_ref} ) {

        # The file name we are given is a Unicode string, but -e doesn't work on
        # those.
        my $file_name = $file_data->[0];
        Cpanel::UTF8::Strict::decode($file_name);
        my $position     = $file_data->[1];
        my $renderer_obj = $file_data->[2] || $self->{'_renderer_obj'};

        die Cpanel::Exception::create( 'InvalidParameter', '[asis,tail_logs] only accepts relative file paths; “[_1]” is not a relative path.', [$file_name] ) if $file_name =~ m{/};

        my $incomplete_file = $self->_file_name_to_path_active($file_name);
        my $complete_file   = $self->_file_name_to_path_completed($file_name);

        my $file_ref;
        if ( -e $incomplete_file ) {
            open( my $fh, '<', $incomplete_file ) or do {
                die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $incomplete_file, mode => '<', error => $! ] );
            };

            $file_ref = {
                'complete_file'   => $complete_file,
                'incomplete_file' => $incomplete_file,
                'file_name'       => $file_name,
                'last_size'       => 0,
                'count'           => 0,
                'fh'              => $fh,
                '_renderer_obj'   => $renderer_obj,

            };
        }
        elsif ( -e $complete_file ) {
            $self->_output_file( $file_name, $complete_file, $position, $renderer_obj );
            next;
        }
        else {
            die Cpanel::Exception::create( 'IO::FileNotFound', 'The system failed to locate either the file “[_1]” or the file “[_2]”.', [ $incomplete_file, $complete_file ] );
        }

        $self->{'log_files'}{$incomplete_file} = $file_ref;

        if ($position) {
            seek( $file_ref->{'fh'}, $position, 0 ) or do {
                die Cpanel::Exception::create( 'IO::FileSeekError', [ path => $incomplete_file, error => $!, position => $position, whence => 0 ] );
            };
        }

        $file_ref->{'fh'}->blocking(0);
    }
    return 1;
}

#$files_ref is an arrayref of: [ [ $path, $start_position_in_file ], .. ]
sub tail_logs {
    my ( $self, $files_ref ) = @_;

    $self->add_log_files($files_ref);

    return $self->_tail_loop();
}

sub _tail_loop {
    my ( $self, $opts ) = @_;

    my $ref;
    while ( scalar keys %{ $self->{'log_files'} } ) {
        foreach my $tail_file ( keys %{ $self->{'log_files'} } ) {
            $ref = $self->{'log_files'}{$tail_file};

            $self->_render_if_update($ref) or do {
                $ref->{'_renderer_obj'}->keepalive() if $ref->{'count'}++ % 4 == 0;
            };

            if ( -e $ref->{'complete_file'} ) {
                $ref->{'fh'}->blocking(1);
                $self->_render_if_update($ref);
                $ref->{'_renderer_obj'}->render_summary() if $ref->{'_renderer_obj'}->can("render_summary");

                delete $self->{'log_files'}{$tail_file};
                next;
            }
        }

        if ( $opts && $opts->{'one_loop'} ) { last; }

        Cpanel::TimeHiRes::sleep(0.25);
    }

    return 1;

}

sub _create_default_renderer_object {
    return Cpanel::LogTailer::Renderer::Generic->new();
}

sub _file_name_to_path_active {
    my ( $self, $file_name ) = @_;

    #Might as well piggy-back...
    return $self->_file_name_to_path_completed(".$file_name");
}

sub _file_name_to_path_completed {
    my ( $self, $file_name ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($file_name);

    return $self->_dir() . "/$file_name";
}

#Returns whether or not there was an update.
sub _render_if_update {
    my ( $self, $file_ref ) = @_;

    local $!;
    my $size = ( stat $file_ref->{'fh'} )[7];
    if ( !$size & $! ) {
        die Cpanel::Exception::create( 'IO::StatError', [ path => $file_ref->{'incomplete_file'}, error => $! ] );
    }

    return 0 if $size <= $file_ref->{'last_size'};

    while ( readline $file_ref->{'fh'} ) {
        $file_ref->{'_renderer_obj'}->render_message( $_, $file_ref->{'file_name'} );
    }
    if ($!) {
        die Cpanel::Exception::create( 'IO::FileReadError', [ path => $file_ref->{'incomplete_file'}, error => $! ] );
    }

    $file_ref->{'last_size'} = tell $file_ref->{'fh'};
    $file_ref->{'count'}     = 0;

    return 1;
}

sub _output_file {
    my ( $self, $file_name, $complete_file, $position, $renderer_obj ) = @_;

    local $!;
    open( my $complete_fh, '<', $complete_file ) or do {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $complete_file, mode => '<', error => $! ] );
    };

    if ($position) {
        seek( $complete_fh, $position, 0 ) or do {
            die Cpanel::Exception::create( 'IO::FileSeekError', [ path => $complete_file, error => $!, position => $position, whence => 0 ] );
        };
    }

    while ( readline $complete_fh ) {
        $renderer_obj->render_message( $_, $file_name );
    }
    if ($!) {
        die Cpanel::Exception::create( 'IO::FileReadError', [ path => $complete_file, error => $! ] );
    }

    close($complete_fh) or warn "close($complete_file) failed: $!";

    $renderer_obj->render_summary() if $renderer_obj->can("render_summary");

    return 1;
}

1;
