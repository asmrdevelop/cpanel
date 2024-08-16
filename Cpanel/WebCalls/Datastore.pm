package Cpanel::WebCalls::Datastore;

# cpanel - Cpanel/WebCalls/Datastore.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Datastore

=head1 DESCRIPTION

This is a base class for modules that access the WebCalls datastore.

=head1 ABOUT THE WEBCALLS DATASTORE

Each webcall entry consists of a key/value dict, described in more detail
in L<Cpanel::WebCalls::Entry>.

The webcalls are stored in per-user directories on disk. Each user’s
directory stores zero or more entries; each entry consists of a JSON file.
Such files are named for the entry’s “ID”; see L<Cpanel::WebCalls::ID> for
details about those IDs.

To facilitate fast lookup, each ID is also stored in a system-wide
webcalls index directory. That directory’s contents consist of symlinks
to the corresponding JSON file in the user directory.

Existence of an entry is defined as existence of the symlink in the
index directory.

=head1 TODO

This should be migrated to call L<Cpanel::Async::FlockFile> underneath.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie          ();
use Cpanel::Exception        ();
use Cpanel::Fcntl::Constants ();
use Cpanel::LoadModule       ();

# exposed for testing
our $_PATH = '/var/cpanel/webcalls';

my $_ENOENT = 2;

my $_TYPE_NS = 'Cpanel::WebCalls::Type';

#----------------------------------------------------------------------

sub _get_lock_p ( $class, $locker_fn, $timeout, $fh = undef ) {
    local ( $@, $! );
    require Cpanel::Async::Flock;
    require Promise::XS;

    local $@;
    $fh ||= do {
        eval { $class->_open_lockfile() } or do {
            return Promise::XS::rejected($@);
        };
    };

    my $lockpath = $class->_get_lockpath();

    my $promise = Cpanel::Async::Flock->can($locker_fn)->( $fh, $lockpath, $timeout );

    return $promise->then( sub { $fh } );
}

sub _get_lockpath ($class) {
    my $dir = $class->_PATH();

    return "$dir/.lock";
}

sub _open_lockfile ($class) {
    my $dir = $class->_PATH();

    my $lockpath = $class->_get_lockpath();

    my $fh;

    local $!;

    # NB: We can’t write to this file because it’ll be problematic
    # for the file to exist before its contents are written.
    my $mode = $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_RDONLY;

    sysopen $fh, $lockpath, $mode, 0700 or do {
        if ( $! == $_ENOENT ) {
            Cpanel::Autodie::mkdir_if_not_exists( $dir, 0700 );

            Cpanel::Autodie::sysopen( $fh, $lockpath, $mode, 0700 );
        }
        else {
            die Cpanel::Exception::create(
                'IO::FileOpenError',
                [
                    mode  => $mode,
                    path  => $lockpath,
                    error => $!,
                ],
            );
        }
    };

    return $fh;
}

sub _type_namespace ( $self, $type ) {
    return Cpanel::LoadModule::load_perl_module("${_TYPE_NS}::$type");
}

sub _index_dir ($self) {
    return "$_PATH/index";
}

sub _user_dir ($self) {
    return "$_PATH/user";
}

sub _PATH {
    return $_PATH;
}

1;
