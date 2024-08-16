package Cpanel::SysPkgs::Base;

# cpanel - Cpanel/SysPkgs/Base.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Carp ();

use Cpanel::EA4::Constants     ();
use Cpanel::OS                 ();
use Cpanel::Pkgr               ();
use Cpanel::Config::LoadCpConf ();

=head1 NAME

Cpanel::SysPkgs::Base

=head1 SYNOPSIS

    package Cpanel::SysPkgs::Pacman;
    use parent 'Cpanel::SysPkgs::Base';
    ...

    sub add_repo {
        open( my $ghost_fh, ">", "/etc/repos.d/namco" );
        my $GAME_OVER = <<~****;
        ================================================.
             .-.   .-.     .--.                         |
            | OO| | OO|   / _.-' .-.   .-.  .-.   .''.  |
            |   | |   |   \  '-. '-'   '-'  '-'   '..'  |
            '^^^' '^^^'    '--'                         |
        ===============.  .-.  .================.  .-.  |
                       | |   | |                |  '-'  |
                       | |   | |                |       |
                       | ':-:' |                |  .-.  |
                       |  '-'  |                |  '-'  |
        ==============='       '================'       |
        ****
        print $fh $GAME_OVER;
        $close $fh;
    }

=head1 DESCRIPTION

This module is the basis for the abstractions needed to handle packager
transactions for the various OSes we support. At the time of this writing,
these include CentOS and Ubuntu (YUM and APT respectively).

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 new

The constructor. If overridden, ideally you will call SUPER as is appropriate,
as much of what might want in the other functionality is setup for you here
already. Accepts no arguments unless overridden in subclass.

=cut

sub new ( $class, $self ) {

    die unless ref $self;
    $self = bless $self, $class;

    if ( !$self->{'output_obj'} || ref $self->{'output_obj'} eq 'HASH' ) {
        if ( $self->{'logger'} ) {
            $self->{'output_is_logger'} = 1;
            $self->{'output_obj'}       = $self->{'logger'};
        }
        else {
            require Cpanel::Output::Formatted::Terminal;
            $self->{'output_obj'} = Cpanel::Output::Formatted::Terminal->new();
        }
    }

    # Defaults
    $self->{'excludes'}        ||= $self->default_exclude_list();
    $self->{'exclude_options'} ||= {};
    $self->{'exclude_remove'}  ||= [];
    $self->{'system_perl_bin'} ||= '/usr/bin/perl';

    return $self;
}

# Used to decide if /usr/bin/perl has been altered in any way.
sub is_system_perl_unaltered ($self) {
    return Cpanel::Pkgr::verify_package( Cpanel::OS::system_package_providing_perl(), $self->{'system_perl_bin'} );
}

# Used to decide if /usr/bin/perl has been altered in any way.
sub is_system_ruby_unaltered ($self) {
    return Cpanel::Pkgr::verify_package( 'ruby', '/usr/bin/ruby' );
}

#----------------------------------------------------------------------

=head2 out, error, warn

These are shortcut functions that just pass the data to the output_obj (logger)
setup for you in the constructor.

=cut

sub out ( $self, @args ) {
    return $self->{'output_obj'}->out(@args);
}

sub error ( $self, @args ) {
    return $self->{'output_obj'}->error(@args);
}

sub warn ( $self, @args ) {
    return $self->{'output_obj'}->warn(@args);
}

=head2 install

"Fail Safe" (doesn't die) method for wrapping `install_packages` defined in
your subclass. Passes in whatever hash of options you might need into the
aforementioned subroutine from @_.

Note: By default the kernel packages are excluded from the install

=cut

sub install ( $self, %opts ) {

    my ( $ret, $err );
    try {
        $ret = $self->install_packages(%opts);
    }
    catch {
        $err = $_;
    };

    if ($err) {
        require Cpanel::Exception;
        my $error_as_string = Cpanel::Exception::get_string($err);
        $self->error($error_as_string);
        return 0;
    }

    return $ret;
}

=head2 update

Same as install, just with a hash keypair tacked on to signal that we want
to update instead of install.

=cut

sub update ( $self, @args ) {
    ref $self or Carp::croak("update() must be called as a method.");

    return $self->install( @args, 'command' => ['update'] );
}

=head2 reinstall

Same as install, just with a hash keypair tacked on to signal that we want
to reinstall instead of install.

=cut

sub reinstall ( $self, @args ) {
    ref $self or Carp::croak("reinstall() must be called as a method.");

    return $self->install( @args, 'command' => ['reinstall'] );
}

=head2 default_exclude_list

Returns a hash of excludes for the given OS. See os.d/$DISTRO/packages.json

=cut

sub default_exclude_list ($self) {

    return Cpanel::OS::system_exclude_rules();
}

=head2 reinit

Reads in the excludes and exclude_options again, as if the constructor was
called.

=cut

sub reinit ( $self, $exclude_options ) {

    $self->{'excludes'}        = $self->default_exclude_list();
    $self->{'exclude_options'} = $exclude_options or die;

    return;
}

=head2 get_repo_details("EA4")

Returns a hashref with `remote_path` (URL) and `local_path` (file).

=cut

sub get_repo_details {
    my ( $self, $repo2eli5 ) = @_;

    my %desc = (
        EA4 => {
            remote_path => scalar( Cpanel::EA4::Constants::repo_file_url() ),     # ea4_from_bare_repo_url
            local_path  => scalar( Cpanel::EA4::Constants::repo_file_path() ),    # ea4_from_bare_repo_path
        }
    );

    die "Unknown repo $repo2eli5" unless exists $desc{$repo2eli5};

    return $desc{$repo2eli5};
}

=head2 add_repo_key, ensure_plugins_turned_on, add_repo, check

More stubs meant to be overridden in subclass.

=cut

sub add_repo_key {
    die "Defined in subclass";
}

sub ensure_plugins_turned_on {
    return;
}

sub add_repo {
    return { 'success' => 1 };
}

=head2 $self->has_exclude_rule_for_package( $pkg )

Check if the package an exclude rule to block future updates.
Returns a boolean:
- true when an exclude rule exist for the package
- false when no exclude rules exist for the package

=cut

sub has_exclude_rule_for_package ( $self, $pkg ) {
    die "Defined in subclass";
}

=head2 $self->drop_exclude_rule_for_package( $pkg )

Drop an exclude rule for the package.
Allowring future package updates.

Returns a boolean:
- true when the exclude was removed (or do not exist)
- false when failed to remove the exclude rule

=cut

sub drop_exclude_rule_for_package ( $self, $pkg ) {
    die "Defined in subclass";
}

=head2 $self->add_exclude_rule_for_package( $pkg )

Add an exclude rule for the package.
Allowring future package updates.

Returns a boolean:
- true when the exclude rule was added (or already exist)
- false when failed to remove the exclude rule

=cut

sub add_exclude_rule_for_package ( $self, $pkg ) {
    die "Defined in subclass";
}

sub setup {
    return;
}

sub check_and_set_exclude_rules {
    die q[check_and_set_exclude_rules: Not implemented];
}

sub validate_excludes ($self) {

    $self->exclude_kernel(1) if $self->should_block_kernel_updates;

    # do not exclude perl updates if perl package is clean
    # An existing perl exclude can be safely removed if perl is unaltered.
    $self->exclude_perl(0) if $self->is_system_perl_unaltered;

    # do not exclude ruby updates if ruby package is clean
    $self->exclude_ruby(0) if $self->is_system_ruby_unaltered;

    return;
}

sub enable_module_stream ( $self, $module, $version ) {
    return;
}

sub disable_module ( $self, $module ) {
    return;
}

sub exclude_kernel ( $self, $set = undef ) {
    return $self->_get_set_exclude_for( 'kernel', $set );
}

sub exclude_ruby ( $self, $set = undef ) {
    return $self->_get_set_exclude_for( 'ruby', $set );
}

sub exclude_perl ( $self, $set = undef ) {
    return $self->_get_set_exclude_for( 'perl', $set );
}

sub exclude_bind_chroot ( $self, $set = undef ) {
    return $self->_get_set_exclude_for( 'bind-chroot', $set );
}

sub _get_set_exclude_for ( $self, $name, $set = undef ) {
    $self->{exclude_options}->{$name} = $set if defined $set;
    return $self->{exclude_options}->{$name} // 0;
}

sub check_is_enabled ($self) {

    # we need a unified documentation... with a single file
    #   this is for legacy documented files (we cannot remove it unless we convert the touch files)
    return if -e '/etc/checkyumdisable';
    return if -e '/etc/checkaptdisable';

    # by default the check is enabled
    return 1;
}

sub should_block_kernel_updates ($self) {

    # we need a unified documentation... with a single file
    #   this is for legacy documented files (we cannot remove it unless we convert the touch files)
    return 1 if -e '/var/cpanel/checkyum-keepkernel';

    # need to convert touch file above to the new format and adjust doc
    return 1 if -e '/var/cpanel/block-kernel-updates';

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return $cpconf->{'rpmup_allow_kernel'} ? 0 : 1;    # do not block kernel by default
}

1;
