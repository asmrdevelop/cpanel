package Cpanel::PackMan::Sys;

# cpanel - Cpanel/PackMan/Sys.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;    # must be after Moo

use IO::Callback            ();
use Cpanel::SafeRun::Object ();
use Cpanel::JSON            ();
use Cpanel::Imports;

our $VERSION = "0.02";

with 'Role::Multiton';

has ext => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { die ref( $_[0] ) . " does not override the ext attribute\n" },
);

has subsystem => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { die ref( $_[0] ) . " does not override the subsystem attribute\n" },
);

has jsoncmd_binary => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { die ref( $_[0] ) . " does not override the jsoncmd_binary attribute\n" },
);

has syscmd_binary => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { die ref( $_[0] ) . " does not override the syscmd_binary attribute\n" },
);

has cmd_failure_hint => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { die ref( $_[0] ) . " does not override the cmd_failure_hint attribute\n" },
);

has repo_conf_pattern => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { die ref( $_[0] ) . " does not override the repo_conf_pattern attribute\n" },
);

has universal_hooks_post_pkg_pattern => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { die ref( $_[0] ) . " does not override the universal_hooks_post_pkg_pattern attribute\n" },
);

sub erase_repo_conf ( $self, $name ) {
    die "erase_repo_conf() name argument required\n" if !length($name);

    my $path = sprintf( $self->repo_conf_pattern, $name );
    unlink $path;
    die "Failed to remove “$path”\n" if -f $path;

    $self->clean;
    $self->cache;

    return $path;
}

sub write_repo_conf ( $self, $name, $content ) {
    die "write_repo_conf() name argument required\n"    if !length($name);
    die "write_repo_conf() content argument required\n" if !length($content);

    require Path::Tiny;
    my $path = sprintf( $self->repo_conf_pattern, $name );
    Path::Tiny::path($path)->spew($content);

    $self->clean;
    $self->cache;

    return $path;
}

sub syscmd_args_txn ( $self, $file ) {
    return $self->_not_implented;
}

sub syscmd_args_txn_dryrun ( $self, $file ) {
    return $self->_not_implented;
}

sub syscmd_line_indicates_headers_are_done ( $self, $line ) {
    return $self->_not_implented;
}

sub info ( $self, $pkg ) {
    return $self->_not_implented;
}

sub multi_info ( $self, %args ) {
    return $self->_not_implented;
}

sub list ( $self, $type, $prefix ) {
    return $self->_not_implented;
}

sub clean ($self) {
    return $self->_not_implented;
}

sub cache ($self) {
    return $self->_not_implented;
}

sub install ( $self, @pkgs ) {
    return $self->_not_implented;
}

sub upgrade ( $self, @pkgs ) {
    return $self->_not_implented;
}

sub uninstall ( $self, @pkgs ) {
    return $self->_not_implented;
}

sub normalize_pkg_hr ( $self, $raw_hr ) {
    return $self->_not_implented;
}

sub parse_lines_for_errors ( $self, $lines_ar ) {
    return $self->_not_implented;
}

sub parse_syscmd_txn_output ( $self, $lines_ar, $trans_data ) {
    return $self->_not_implented;
}

sub is_unavailable ($self) {
    return $self->_not_implented;
}

sub syscmd ( $self, $line_handler, $subcmd, @args ) {

    local $ENV{LANG}        = "C";    # isn't local() via before_exec => sub { $ENV{LANG} = "C" },
    local $ENV{LANGUAGE}    = "C";
    local $ENV{LC_ALL}      = "C";
    local $ENV{LC_MESSAGES} = "C";
    local $ENV{LC_CTYPE}    = "C";

    my $syscmd_binary   = $self->syscmd_binary;
    my $combined_output = '';
    my $output_handler  = IO::Callback->new( ">", sub { $combined_output .= shift } );

    if ( $ENV{PACKMAN_DEBUG} ) {
        print "➜➜➜➜ PACKMAN_DEBUG syscmd()\n";
        print "ENV:\n";
        for my $ev ( sort keys %ENV ) {
            print "\t$ev: $ENV{$ev}\n";
        }
        print "\nCMD: $syscmd_binary $subcmd " . join( " ", @args ) . "\n";
        print "\n … done (PACKMAN_DEBUG syscmd())\n";
    }

    eval {
        Cpanel::SafeRun::Object->new_or_die(
            program => $syscmd_binary,
            args    => [ $subcmd, @args ],
            stdout  => $output_handler,
            stderr  => $output_handler,
        );
    };
    if ($@) {
        my @pretty           = map { ( $_ eq "" || !defined $_ ) ? '""' : $_ } @args;
        my $cmd_failure_hint = $self->cmd_failure_hint;
        die $@->to_locale_string_no_id() . " w/ $syscmd_binary $subcmd @pretty\n$combined_output\nOften errors like this can be resolved by running `$cmd_failure_hint`\n";
    }

    my @shell_output = split( m/\n/, $combined_output );    # if this is refactored to build @shell_output as we go KIM that IO::Callback will send mutilple lines to in $_[0]
    my $headers_done = 0;
    for my $line (@shell_output) {
        if ( !$headers_done ) {
            $headers_done = $self->syscmd_line_indicates_headers_are_done($line);
            next if !$headers_done || ( $headers_done && $headers_done == 1 );    # 1 means do not pass final header line to $handler->(), otherwise go ahead and process the $line
        }

        chomp $line;
        my $handler_retval = $line_handler->("$line\n");
        my $output         = defined $handler_retval ? $handler_retval : '';
        print $output;
    }

    return 1;
}

sub jsoncmd ( $self, $path, @args ) {
    my $run;
    my $jsoncmd_binary = $self->jsoncmd_binary;
    eval {
        $run = Cpanel::SafeRun::Object->new_or_die(
            'program' => $jsoncmd_binary,
            'args'    => [ $path, @args ]
        );
    };
    if ($@) {
        my @pretty           = map { ( $_ eq "" || !defined $_ ) ? '""' : $_ } @args;
        my $cmd_failure_hint = $self->cmd_failure_hint;
        die $@->to_locale_string_no_id() . " w/ $path @pretty\nOften errors like this can be resolved by running `$cmd_failure_hint`\n";
    }

    # TODO/YAGNI:
    # factor in $run->stderr() ? probably via IO::Callback like Cpanel::PackMan’s resolution methods:
    #    my $combined_output = '';
    #    my $output_handler  = IO::Callback->new( ">", sub { $combined_output .= shift } );
    #    $run = Cpanel::SafeRun::Object->new_or_die(
    #    …
    #        stdout => $output_handler,
    #        stderr => $output_handler,
    #    …
    my $result_hr;
    eval { $result_hr = Cpanel::JSON::Load( ( split( /JSON_OUTPUT_HEADER\n/, $run->stdout() ) )[-1] ); };
    if ($@) {
        logger->debug( "Failed to read JSON output from $path: $@: " . substr( $run->stdout(), 0, 256 ) );
        return;
    }

    return $result_hr;
}

###############
#### helpers ##
###############

sub _not_implented ($self) {
    my @caller = caller(1);
    my ($meth) = reverse( split( /::/, $caller[3] ) );
    die ref($self) . " does not implement $meth()\n";
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::PackMan::Sys - Interact with the server’s package management system

=head1 VERSION

This document describes Cpanel::PackMan::Sys version 0.02

=head1 SYNOPSIS

    package Cpanel::PackMan::Sys::package_system_in_question;

    use cPstrict;
    use Moo;
    extends 'Cpanel::PackMan::Sys';

    … implement interface for package_system_in_question here …

=head1 DESCRIPTION

This class defines the interface to allow PackMan to interact consistely with any package system via package system specific subclasses.

The subclass used is based on C<Cpanel::OS::package_manger>.

=head1 INTERFACE

This class and its subclasses are intended to be used by Cpanel::PackMan. If non-Cpanel::PackMan code is using this object it is likley something bad is happening. non-Cpanel::PackMan code should only use Cpanel::PackMan methods.

The exceptions are these 9 methods:

=over

=item $pm->sys->clean()

=item $pm->sys->cache()

=item $pm->sys->install(@pkgs)

=item $pm->sys->upgrade(@pkgs)

=item $pm->sys->uninstall(@pkgs)

=item $pm->sys->write_repo_conf($name, $content)

=item $pm->sys->erase_repo_conf($name)

=item $pm->sys->repo_conf_pattern

For display or readonly ops only. Use C<write_repo_conf()> and C<erase_repo_conf()> to manipulate the file itself since its more than file system manipulation.

=item $pm->sys->universal_hooks_post_pkg_pattern

=back

=head2 Must be defined by package system subclass

If the sub class does not define one of these a fatal error to that effect will be thrown.

=head3 ATTRIBUTES

All of these are Readonly and not settable via constructor.

=head4 ext

The file extension the package manager uses for its package files/URLs. This is for deipslay purposes only. Do not use this to decide what to do in your code. Doing so will add tech debt that will need addressed as we add new package management types. Instead use the abstract C<Cpanel::PackMan> or L<Cpanel::OS>.

=head4 subsystem

The subsystem the package manager sits on top of. This should also be a command that, by default, is in PATH.

=head4 jsoncmd_binary

The binary used to execute a “JSON Script” for the package system. Used by C<jsoncmd>.

=head4 syscmd_binary

The binary to use to execute subcommands for the package system. Used by C<syscmd>.

=head4 cmd_failure_hint

The command to tell users to try running to rectify issues when C<jsoncmd> or C<syscmd> fail.

=head4 repo_conf_pattern

The printf pattern for the package system’s `<DIR>/%s.<EXT>`.

=head4 universal_hooks_post_pkg_pattern

The printf pattern for the package system’s universal hook path for a post transaction for a given package.

The first C<%s> is the package name, the second C<%s> is hook script name.

=head3 METHODS

=head4 syscmd_args_txn($file)

Takes a tempfile containing C<install PKGS>, C<uninstall PKGS>, C<upgrade PKGS> commands (one per line), updates it as needed by the package system, and returns args to do those commands as once.

For example, C<yum> changes C<uninstall> to C<erase>, appends a line C<run\n>, and returns 3 arguments for its C<syscmd_binary>: C<-y shell $file>

=head4 syscmd_args_txn_dryrun($file)

Same as C<syscmd_args_txn()> except it returns arguments to do a dryrun of the commands.

For example, C<yum> returns C<--assumeno shell $file>.

=head4 syscmd_line_indicates_headers_are_done($line)

Some systems have “header” output when C<syscmd_binary> is executed that we want to skip when examining its output.

Given a line of output it should:

… return C<1> if the line indicates the last line of header output.

… return C<2> if the line is one that comes after headers (maybe no headers were output).

… return C<0> otherwise.

=head4 info($pkg)

Get the raw hashref for the given package from the the package system. It is normalized for public consumption in C<Cpanel::PackMan> by C<normalize_pkg_hr()>.

=head4 multi_info(%args)

Returns an array ref of C<info()> raw data hashefs. Each one is normalized for public consumption in C<Cpanel::PackMan> by C<normalize_pkg_hr()>.

C<%args> can have the following keys:

=over

=item populate-provides

If not given or if true include each package’s provides info.

=item disable-excludes

If true, excluded packages should be included.

=item packages

An array ref of packages to include.

=item prefixes

An array ref of prefixes to incldue. e.g. C<ea-> would incldue all EA4 packages.

=back

=head4 list($type, $prefix)

Get an array ref of packages from the the package system. Public consumption happens in C<Cpanel::PackMan>.

C<$type> can be C<all>, C<available>, C<updates>, or C<installed>. If not given it should default to C<all>.

C<$prefix> is a string to match the beginning of the packages you are interested in, e.g. C<ea->.

=head4 clean()

Call C<syscmd()> to clean up the package manager state. Should die on failure.

=head4 cache()

Call C<syscmd()> to freshen up the package manager caches. Should die on failure.

=head4 install(@pkgs)

Call C<syscmd()> to install C<@pkgs> non-interactively. Should die on failure.

The last argument can optionally be a L</flags hash> hashref.

=head4 upgrade(@pkgs)

Call C<syscmd()> to upgrade C<@pkgs> non-interactively. Should die on failure.

The last argument can optionally be a L</flags hash> hashref.

=head4 uninstall(@pkgs)

Call C<syscmd()> to uninstall C<@pkgs> non-interactively. Should die on failure.

=head4 normalize_pkg_hr($raw_hr)

This should take the package system’s raw hr (from C<info()>) and return a normalizes version of the hashref described in L<Cpanel::PackMan>’s C<pkg_hr()> documentation.

=head4 parse_lines_for_errors($lines_ar)

This should take an array ref of output from C<syscmd_binary> and return any fatal errors. Errors that are not a failure (e.g. trying another mirror) should not be included.

=head4 parse_syscmd_txn_output($lines_ar, $trans_data)

This should take an array ref of output from C<syscmd_binary> multi op dryrun transaction, populate C<$trans_data>, and return errors like C<parse_lines_for_errors()> does.

Populating C<$trans_data> entails adding packages to the keys (value is irrelevant) C<upgrade>, C<install>, C<uninstall>, and C<unaffected>.

=head4 is_unavailable()

Returns true when the package system is unavailable to do a task (e.g. locked, running, updating cache, etc).

Otherwise returns false.

=head4 flags hash

Methods that take a “flags hash” can pass, as their final argument, a hashref with the following keys:

=over

=item only_from_repos

This should be an array ref of repo names that the given packages are in. It will make the operation only use the given repos.

=back

=head2 Methods not intended to be overridden by package system subclass

=head3 syscmd($handler, $subcmd, @args)

Execute C<syscmd_binary $subcmd @args>, passing output through C<$handler>. Throws detailed error when it fails.

=head3 jsoncmd($path, @args)

Execute <jsoncmd_binary $path @args>. Where C<$path> is a “JSON Script”. Throws detailed error when it fails.

A “JSON Script” is a script that outputs, at the end, the line C<JSON_OUTPUT_HEADER\n> followed by a JSON string.

=head3 erase_repo_conf($name)

Erase the repo conf $name (based on repo_conf_pattern()), clean(), and cache().

Returns the full path on success.

=head3 write_repo_conf($name, $content)

Write $content to $name (based on repo_conf_pattern()), clean(), and cache().

Returns the full path on success.
