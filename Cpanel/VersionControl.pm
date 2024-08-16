package Cpanel::VersionControl;

# cpanel - Cpanel/VersionControl.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::VersionControl

=head1 SYNOPSIS

    use Cpanel::VersionControl ();

    my $vc = Cpanel::VersionControl->new( 'type' => 'git', ... );

    my @types = Cpanel::VersionControl->supported_types();

=head1 DESCRIPTION

Cpanel::VersionControl is the primary interface for interacting with
supported version control systems.  The Cpanel::VersionControl module
should serve as a system-agnostic frontend to any of the version
control systems we may wish to support.

This module is intended to be subclassed and extended to provide
support for some given version control system.

=cut

use strict;
use warnings;

use Cpanel::Exception        ();
use Cpanel::LoadModule       ();
use Cpanel::LoadModule::Name ();
use Cpanel::PwCache          ();
use Cpanel::SafeDir::MK      ();
use Time::HiRes              ();

use Fcntl;

# The base path for logging during long-running operations.
our $LOG_PATH = '/.cpanel/logs';

my $logger;

=head1 CLASS METHODS

All methods will validate whether they have received the correct
arguments, and will throw a Cpanel::Exception if a required argument
is missing.

All methods will take arguments in a hash style, e.g.

    $vc->foo( 'arg1' => 'val1', 'arg2' => 'val2', ... );

=head2 Cpanel::VersionControl-E<gt>new()

Creates a new object

=head3 Required argument keys

=over 4

=item type

The type of version-control system we want to work with.  The
parameter which is passed in will be forced to lowercase before
attempting to load the submodule.

=back

=head3 Returns

An object of the requested type.

=head3 Dies

=over 4

=item *

If the type argument is missing

=item *

If the support module for the type we want can not be loaded

=back

=cut

sub new {
    my ( $class, %args ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'type' ] )
      unless defined $args{'type'};

    my $pkg = __PACKAGE__ . '::' . lc( $args{'type'} );
    Cpanel::LoadModule::load_perl_module($pkg);

    return $pkg->new(%args);
}

=head2 Cpanel::VersionControl->supported_types()

Provide a list of VCS modules that we can find.

=head3 Returns

A list of the supported modules.

=cut

sub supported_types {
    my @mods = ();

    my $base = __PACKAGE__;
    $base =~ s~::~/~g;

    for my $dir (@INC) {

        # The module to support a given VCS will be named as all lowercase
        push @mods, grep { !m/[A-Z]/ } Cpanel::LoadModule::Name::get_module_names_from_directory("$dir/$base");
    }

    return @mods;
}

=head1 SUBCLASSING

The Cpanel::VersionControl object is intended to be subclassed in
order to support any given version control system.  There are a
handful of abstract methods, described below, which should be
implemented in each subclass.

The subclass should have a final module name in all-lowercase, such as
Cpanel::VersionControl::somevcs, which would correspond with the
'somevcs' type.

Each type should use the C<repository_root> key within the object hash
as its unique key, which also contains the absolute path of the
repository's root on disk.

Any given version control system may need fields which don't
correspond with any other version control system, so the structure of
each type is open-ended.  Every subclass should use the field
C<repository_root> to represent the absolute root directory of a
repository, but any other fields are up to the requirements of the
class or underlying version control system.

Subclasses may opt to pull data directly from the repositories they
manage, instead of caching information within the object
representation; they can do this by using methods which are named for
the field they wish to support.  For example, an C<available_branches>
field can become out of date very quickly, so the object can provide
just-in-time data by simply pulling the information out of the
repository at the time of request via an C<available_branches()>
method.  Each of these method names should be provided by the
C<supported_methods()> method.

The API layer can take all public fields, and public methods provided
by the C<supported_methods()> method, and provide them to callers
seamlessly.

See the L<Cpanel::VersionControl::git> module for an example.

=head1 ABSTRACT METHODS

These are the methods which subclasses should implement in order to be
fully-functional modules.  Each of these methods will die with an
'Unimplemented' message unless implemented in a subclass.

=head2 $vc-E<gt>type()

The type of version-control system the repository uses.  Returns a
string, which should be the final name component of the module in
question, e.g. the Cpanel::VersionControl::testing::type() method
should return 'testing'.

=cut

sub type {
    die 'Unimplemented';
}

=head2 $vc-E<gt>create()

The function to do the actual creation of the repository on disk.

Some version-control repositories may take a significant amount of
time to create, if they are being cloned or downloaded from a central
repository.  Requiring the UI to wait for a lengthy period in order to
do the creation would be inappropriate in these cases.  For this
reason, the create method may be spawned off as a Cpanel::UserTasks
item by the following method:

    use Cpanel::UserTasks ();

    Cpanel::UserTasks->new()->add(
        'subsystem' => 'VersionControl',
        'action'    => 'create',
        'args'      => { 'repository_root' => $repository_root,
                         'log_file'        => $log_file,
                       }
    );

=cut

sub create {
    die 'Unimplemented';
}

=head2 $vc-E<gt>update()

Change one or more of the parameters about a repository.  The
C<repository_root> should be considered immutable.

This method should always update itself within the cache.

=cut

sub update {
    die 'Unimplemented';
}

=head2 $vc-E<gt>remove()

Remove the repository.  This method may take multiple approaches.  It
may completely remove the repository's root directory, and everything
underneath it.  It may or may not place the removed files into a trash
area.  Or it could remove just the control files which make it into a
repository, to render the directory tree as just a collection of
files.

It should also invalidate the current object, and remove it from the
cache.

=cut

sub remove {
    die 'Unimplemented';
}

=head2 $vc-E<gt>serialize()

Serialize an object.

=head2 $class-E<gt>deserialize()

Deserialize an object.

These should transform an object to and from an unblessed reference
which would be suitable for JSON encoding.

=cut

sub serialize {
    die 'Unimplemented';
}

sub deserialize {
    die 'Unimplemented';
}

=head1 BASE METHODS

=head2 $vc-E<gt>deployable()

Return a 0/1 if the repository has a deployment configuration
available.  The presence of the C<.cpanel.yml> control file in the
root of the repository will be the signal.

=cut

sub deployable {
    my ($self) = @_;

    return -f "$self->{'repository_root'}/.cpanel.yml" || 0;
}

=head2 $vc-E<gt>supported_methods()

Return a list of the field names that are supported by methods.

The C<Cpanel::VersionControl> object provides only the C<deployable()>
method.  Each subclass that supports specific field names as public
method calls should override this method to add those field/method
names into the arrayref that it returns.

Subclasses should always add to the results of the returned list,
rather than making any assumptions about contents of the list.

=cut

sub supported_methods {
    my ($self) = @_;

    return ['deployable'];
}

=head2 $vc-E<gt>log_file()

When we do operations as task queue items, we need to be able to log
the results in a log file of our own choosing.  We'll put together a
standard-ish log file naming scheme that any subclass can use.

=head3 Arguments

=over 4

=item $operation

The name of the operation that's being done, e.g. 'create', 'deploy'.
This will be included in the log filename.

=back

=cut

sub log_file {
    my ( $self, $operation ) = @_;

    my $home = Cpanel::PwCache::gethomedir();
    my $path = "$home$LOG_PATH";
    my $time = Time::HiRes::gettimeofday();
    my $type = $self->type();
    my $log  = "${path}/vc_${time}_${type}_${operation}.log";

    Cpanel::SafeDir::MK::safemkdir($path);
    open( my $fh, '>', $log )
      or die Cpanel::Exception::create(
        'IO::FileOpenError',
        [ 'path' => $log, 'error' => $!, 'mode' => '>' ]
      );

    return ( $log, $fh );
}

# Private methods
sub _logger {
    return $logger ||= do {
        Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
        Cpanel::Logger->new();
    };
}

=head1 CONFIGURATION AND ENVIRONMENT

There are no configuration files or environment variables which
are required or produced by this module.

=head1 DEPENDENCIES

L<Cpanel::Exception>, L<Cpanel::LoadModule>,
L<Cpanel::LoadModule::Name>, L<Cpanel::PwCache>, and L<Cpanel::SafeDir::MK>.

=head1 TODO

The L<Cpanel::LoadModule> module doesn't handle use of the
$L<Cpanel::ConfigFiles>::CUSTOM_PERL_MODULES_DIR directory, so we
can't load modules from there.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2018, cPanel, Inc.  All rights reserved.  This code is
subject to the cPanel license.  Unauthorized copying is prohibited.

=cut

1;
