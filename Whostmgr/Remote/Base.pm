package Whostmgr::Remote::Base;

# cpanel - Whostmgr/Remote/Base.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Remote::Base

=head1 DESCRIPTION

This module houses logic shared by multiple L<Whostmgr::Remote>-like
modules.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use String::ShellQuote ();

use Cpanel::Encoder::Tiny   ();
use Cpanel::Exception       ();
use Cpanel::FileUtils::Path ();
use Whostmgr::Remote::State ();

use Whostmgr::Transfers::Version ();

my $DEFAULT_LOCALE = 'C';

our $CUSTOM_PKGACCT_DIR = '/var/cpanel/lib/Whostmgr/Pkgacct';
our $LOCAL_PKGACCT_DIR  = '/usr/local/cpanel/Whostmgr/Pkgacct';

# This is the order of returns from remoteexec().
our ( $STATUS, $MESSAGE, $RAWOUT, $REMOTE_USERNAME, $REMOTE_ARCHIVE_IS_SPLIT, $REMOTE_FILE_PATHS, $REMOTE_FILE_MD5SUMS, $RESULT, $REMOTE_FILE_SIZES, $ESCALATION_METHOD_USED ) = ( 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 );

#----------------------------------------------------------------------

=head1 METHODS

=head2 @returns = I<OBJ>->remoteexec( .. )

See child classes for a description of this function’s interface.

=cut

sub remoteexec {
    my ( $self, %VALS ) = @_;

    return ( 0, locale()->maketext( "“[_1]” requires the “[_2]” argument.", 'remoteexec', 'cmd' ) ) if !$VALS{'cmd'};

    # NB: We assume that if $VALS{'cmd'} is an array ref,
    # then that array’s first element contains no spaces.
    # Since this tool is used only in cPanel-controlled code and
    # only to call “normal-looking” things like cat and pkgacct that
    # shouldn’t be an issue, but it’s worth noting.

    my $remote_command_to_exec = ( ref $VALS{'cmd'} ? join( " ", @{ $VALS{'cmd'} } ) : $VALS{'cmd'} );

    return $self->_remoteexec_command( $remote_command_to_exec, %VALS );
}

=head2 @returns = I<OBJ>->remotecopy( %OPTS )

Downloads or uploads a given file.

%OPTS are:

=over

=item * C<direction>: either C<upload> or C<download>

=item * C<srcfile>

=item * C<destfile>

=item * C<callback> - for percentages

=item * C<size> - A hint as to the size of the file (uploads only)

=item * C<txt> - A way to “announce” what this is going to do;
printed to STDOUT at the start of the task.

=back

Returns at I<least> a two-part return; see the subclasses for further
details.

=cut

sub remotecopy {
    my ( $self, %VALS ) = @_;

    die "FTP Support removed" if $VALS{'useftp'};

    foreach my $arg (qw(direction srcfile destfile)) {
        return ( 0, locale()->maketext( "“[_1]” requires the “[_2]” argument.", 'remotecopy', $arg ) ) if !$VALS{$arg};
    }

    return $self->_remotecopy_post_validation(%VALS);
}

=head2 ( $ok_yn, $result_hr ) = I<OBJ>->cat_files( \@PATHS )

Like C<remotecopy()> in C<download> mode. (Essentially redundant?)

@PATHS are remote paths. The return is two-part, with the success payload
being a hashref of ( path => contentstring ).

=cut

sub cat_files ( $self, $paths ) {

    die Cpanel::Exception::create( 'InvalidParameter', 'The argument must be an [asis,arrayref] of file paths.' ) if ref $paths ne 'ARRAY';

    return $self->multi_exec( [ map { { 'key' => $_, 'arguments' => $_, 'shell_safe_command' => '/bin/cat', 'locale' => $Whostmgr::Remote::State::UTF8_LOCALE } } @{$paths} ] );
}

=head2 ( $ok_yn, $content ) = I<OBJ>->cat_file( $PATH )

Like C<remotecopy()> in C<download> mode. (Essentially redundant?)

$PATH is a remote path. The return is two-part; the success payload
is the file contents (a string).

=cut

sub cat_file ( $self, $path ) {

    my ( $cat_status, $cat_results ) = $self->cat_files( [$path] );

    return ( $cat_status, $cat_results ) if !$cat_status;

    return ( 1, $cat_results->{$path} );
}

=head2 ( $ok_yn, $md5_hex ) = I<OBJ>->get_md5sum_for( $PATH )

Like C<cat_file()> but returns a hex string that represents $PATH’s
MD5 sum instead of its content.

=cut

sub get_md5sum_for ( $self, $file ) {

    return unless $file;

    my ( $shell_quoted_file_ok, $shell_quoted_file ) = $self->_shell_quote($file);

    return if !$shell_quoted_file_ok;

    my $html_encoded_file = Cpanel::Encoder::Tiny::safe_html_encode_str($file);

    my ( $status, $result ) = (
        $self->remoteexec(
            'txt'          => locale()->maketext( 'Fetching md5sum of “[_1]” from the remote server …', $html_encoded_file ),
            'returnresult' => 1,
            'cmd'          => qq{[ -e $shell_quoted_file ] && ( which md5sum 2>/dev/null && md5sum $shell_quoted_file ) || ( which md5 2>/dev/null && md5 -r $shell_quoted_file )},
        )
    )[ $STATUS, $RESULT ];

    if ( !$status ) {
        warn "Failed to get MD5 sum for remote “$file”: $result";
        return;
    }

    if ( $result && $result =~ m{([0-9a-f]{32})\s+$file} ) {
        return $1;
    }

    return;
}

=head2 ($ok_yn, $key_output_hr) = I<OBJ>->multi_exec( \@COMMANDS )

Documentation pending. (sorry)

=cut

sub multi_exec ( $self, $command_input ) {

    my ( $parse_ok, $commands ) = $self->_parse_multi_exec_commands_input_into_shell_commands($command_input);
    return ( $parse_ok, $commands ) if !$parse_ok;

    return $self->_multi_exec_shell_commands($commands);
}

=head2 $dirpath = I<CLASS>->remotescriptdir( \@COMMANDS )

Documentation pending. (sorry)

=cut

sub remotescriptdir ( $self, $servtype ) {

    return Whostmgr::Transfers::Version::servtype_version_compare( $servtype, '>=', '11.30' ) ? '/usr/local/cpanel/scripts' : '/scripts';
}

sub _get_default_destfile_for_remotescriptcopy ( $, $srcfile ) {
    return ( Cpanel::FileUtils::Path::dir_and_file_from_path($srcfile) )[1];
}

=head2 @output = I<OBJ>->remotescriptcopy( %OPTS )

Documentation pending. (sorry)

=cut

sub remotescriptcopy ( $self, %CFG ) {

    my $srcfile  = $CFG{'srcfile'}  || die "remotescriptcopy requires the “srcfile” argument";
    my $destfile = $CFG{'destfile'} || $self->_get_default_destfile_for_remotescriptcopy($srcfile);

    my $scriptdir = $self->{'scriptdir'} || die "remotescriptcopy requires “scriptdir” to be defined in the object";

    my $src_file_path;
    if ( 0 == rindex( $srcfile, '/', 0 ) ) {
        $src_file_path = $srcfile;
    }
    else {
        my $srcpath = $self->_determine_local_file_srcpath($srcfile);
        $src_file_path = "$srcpath/$srcfile";
    }

    if ( !-e $src_file_path ) {
        return ( 0, locale()->maketext( "“[_1]” cannot be copied to the remote server because it does not exist locally.", $src_file_path ) );
    }

    my $html_encoded_src_file_path = Cpanel::Encoder::Tiny::safe_html_encode_str($src_file_path);

    my $dest_file_path              = $self->_remotescriptcopy_first_destination($destfile);
    my $html_encoded_dest_file_path = Cpanel::Encoder::Tiny::safe_html_encode_str($dest_file_path);

    my @ret = $self->remotecopy(
        'txt'       => locale()->maketext( "Copying “[_1]” to “[_2]” …", $html_encoded_src_file_path, $html_encoded_dest_file_path ),
        "direction" => "upload",
        "srcfile"   => $src_file_path,
        "destfile"  => $dest_file_path,
    );

    if ( !$ret[0] ) {
        print locale()->maketext( "Unable to copy “[_1]”.", $html_encoded_src_file_path ) . "\n";
    }

    return @ret;
}

sub _remotescriptcopy_first_destination ( $self, $destfile ) {
    return "$self->{'scriptdir'}/$destfile";
}

=head2 @output = I<OBJ>->remotescriptexec( %OPTS )

Documentation pending. (sorry)

=cut

sub remotescriptexec ( $self, %CFG ) {

    my $execfile = $CFG{'execfile'} || die "remotescriptexec requires the “execfile” argument";

    my $scriptdir = $self->{'scriptdir'} || die "remotescriptexec requires 'scriptdir' to be defined in the object";

    my $remote_script       = "$scriptdir/$execfile";
    my $html_encoded_script = Cpanel::Encoder::Tiny::safe_html_encode_str($remote_script);

    my @ret = $self->remoteexec(
        'txt' => locale()->maketext( "Running “[_1]” …", $html_encoded_script ),
        "cmd" => $remote_script,
    );

    if ( !$ret[0] ) {
        print locale()->maketext( "Unable to run the command “[_1]”.", $html_encoded_script ) . "\n";
    }

    return @ret;
}

#----------------------------------------------------------------------

sub _determine_local_file_srcpath {
    my ( $self, $srcfile ) = @_;

    my $enable_custom_pkgacct = $self->{'enable_custom_pkgacct'};
    die "remotescriptcopy requires “enable_custom_pkgacct” to be defined in the object" if !defined $enable_custom_pkgacct;

    if ( $enable_custom_pkgacct && -e "$CUSTOM_PKGACCT_DIR/$srcfile" ) {
        if ($Whostmgr::Remote::State::HTML) {
            print locale()->maketext( "Using custom pkgacct code at: “[output,strong,_1]”.", Cpanel::Encoder::Tiny::safe_html_encode_str("$CUSTOM_PKGACCT_DIR/$srcfile") ) . "<br />\n";
        }
        else {
            print locale()->maketext( "Using custom pkgacct code at: “[_1]”.", "$CUSTOM_PKGACCT_DIR/$srcfile" ) . "\n";
        }
        return $CUSTOM_PKGACCT_DIR;
    }
    elsif ( -e "$LOCAL_PKGACCT_DIR/$srcfile" ) {
        if ($Whostmgr::Remote::State::HTML) {
            print locale()->maketext( "Using local pkgacct code at: “[output,strong,_1]”.", Cpanel::Encoder::Tiny::safe_html_encode_str("$LOCAL_PKGACCT_DIR/$srcfile") ) . "<br />\n";
        }
        else {
            print locale()->maketext( "Using local pkgacct code at: “[_1]”.", "$LOCAL_PKGACCT_DIR/$srcfile" ) . "\n";
        }
        return $LOCAL_PKGACCT_DIR;
    }

    return '/usr/local/cpanel/scripts';
}

sub _shell_quote {
    my ( $self, $unsafe_command ) = @_;

    my $safe_command;
    eval { $safe_command = String::ShellQuote::shell_quote($unsafe_command); };
    if ( !$safe_command ) {
        return ( 0, locale()->maketext( "Unable to safely quote the commands “[_1]” (so it was skipped): [_2]", Cpanel::Encoder::Tiny::safe_html_encode_str($unsafe_command), $@ ) );
    }
    return ( 1, $safe_command );
}

sub _parse_multi_exec_commands_input_into_shell_commands {
    my ( $self, $command_input ) = @_;

    my $ids = 1;
    my %commands;

    foreach my $cmdkey ( @{$command_input} ) {
        my $key  = $cmdkey->{'key'} or die 'multi_exec command needs “key”';
        my $safe = {};

        foreach my $arg (qw(command arguments)) {
            if ( $cmdkey->{ 'shell_safe_' . $arg } ) {
                $safe->{$arg} = $cmdkey->{ 'shell_safe_' . $arg };
            }
            else {
                my ( $shell_safe_ok, $shell_safe_command ) = $self->_shell_quote( $cmdkey->{$arg} );
                return ( $shell_safe_ok, $shell_safe_command ) if !$shell_safe_ok;
                $safe->{$arg} = $shell_safe_command;
            }
        }

        $commands{$key} = {
            'command' => "$safe->{'command'} $safe->{'arguments'} 2>/dev/null",
            'locale'  => ( $cmdkey->{'locale'} || $DEFAULT_LOCALE ),
            'id'      => $ids++
        };
    }

    return ( 1, \%commands );
}

1;
