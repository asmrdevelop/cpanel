package Cpanel::SafeDir::Fixup;

# cpanel - Cpanel/SafeDir/Fixup.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::SafeDir::Fixup

=head1 SYNOPSIS

    use Cpanel::SafeDir::Fixup ();
    my $homedir_path    = Cpanel::SafeDir::Fixup::homedirfixup( $path );
    my $maildir_path    = Cpanel::SafeDir::Fixup::maildirfixup( $path );
    my $publichtml_path = Cpanel::SafeDir::Fixup::publichtmldirfixup( $path );

=head1 DESCRIPTION

Clean up and prepend paths with a specified directory.

=head1 METHODS

=head2 maildirfixup

=head3 Purpose

Prepend a path with the user's maildir directory.

=head3 Arguments

=over 3

=item C<< dir >> [in, required]

STRING - The path to fixup.

=item C<< homedir >> [in, optional]

STRING - The path to the user's home directory.

Defaults to C<$Cpanel::homedir>.

=item C<< abshomedir >> [in, optional]

STRING - The absolute path to the user's home directory.

Defaults to C<$Cpanel::abshomedir>.

=item C<< acct >> [in, optional]

STRING - The username of the account

Defaults to C<$Cpanel::authuser> if called from webmail.

=back

=head3 Returns

A string containing the fixed up path.

=cut

sub maildirfixup {
    my $dir        = shift;
    my $homedir    = shift;
    my $abshomedir = shift;
    my $acct       = shift;
    my $basedir    = 'mail';
    if ( defined $Cpanel::appname && $Cpanel::appname eq 'webmail' && $Cpanel::authuser =~ /\@/ ) {
        $acct = $Cpanel::authuser;
    }
    if ( $acct && $acct =~ /\@/ ) {
        my ( $user, $domain ) = split( /\@/, $acct );
        $user   =~ s/\///g;
        $domain =~ s/\///g;
        $domain =~ tr/\.//s;
        $basedir = 'mail/' . $domain . '/' . $user;
    }
    if ( !$homedir )    { $homedir    = $Cpanel::homedir    // ''; }
    if ( !$abshomedir ) { $abshomedir = $Cpanel::abshomedir // ''; }
    $dir =~ s/^$basedir//;
    my $did_strip_abshomedir = ( $dir =~ s/^$abshomedir(\/$basedir)?// );
    if ( !$did_strip_abshomedir ) {
        $dir =~ s/^$homedir(\/$basedir)?//;
    }

    # TODO: Update this to use the _strip sub
    $dir =~ s/\.\.//g;
    $dir = "$abshomedir/$basedir/$dir";
    $dir =~ s{//+}{/}g;
    $dir =~ s/\/$//g;
    return $dir;
}

=head2 publichtmldirfixup

=head3 Purpose

Prepend a path with the user's B<public_html> directory.

=head3 Arguments

=over 3

=item C<< dir >> [in, required]

STRING - The path to fixup.

=item C<< homedir >> [in, optional]

STRING - The path to the user's home directory.

Defaults to C<$Cpanel::homedir>.

=item C<< abshomedir >> [in, optional]

STRING - The absolute path to the user's home directory.

Defaults to C<$Cpanel::abshomedir>.

=back

=head3 Returns

A string containing the fixed up path.

=cut

sub publichtmldirfixup {
    my $dir        = shift;
    my $homedir    = shift;
    my $abshomedir = shift;
    if ( !$homedir )    { $homedir    = $Cpanel::homedir; }
    if ( !$abshomedir ) { $abshomedir = $Cpanel::abshomedir; }
    $dir =~ s/\n//g;
    $dir =~ s/^public_html//;
    my $did_strip_abshomedir = ( $dir =~ s/^$abshomedir(\/public_html)?// );

    if ( !$did_strip_abshomedir ) {
        $dir =~ s/^$homedir(\/public_html)?//;
    }

    # TODO: Update this to use the _strip sub
    $dir =~ s/\.\.//g;
    $dir = "$abshomedir/public_html/$dir";
    $dir =~ s{//+}{/}g;
    $dir =~ s/\/$//g;
    return $dir;
}

=head2 homedirfixup

=head3 Purpose

Prepend a path with the user's home directory.

=head3 Arguments

=over 3

=item C<< dir >> [in, required]

STRING - The path to fixup.

=item C<< homedir >> [in, optional]

STRING - The path to the user's home directory.

Defaults to C<$Cpanel::homedir>.

=item C<< abshomedir >> [in, optional]

STRING - The absolute path to the user's home directory.

Defaults to C<$Cpanel::abshomedir>.

=back

=head3 Returns

A string containing the fixed up path.

=cut

sub homedirfixup {
    my $dir        = shift;
    my $homedir    = shift;
    my $abshomedir = shift;
    if ( !$homedir )    { $homedir    = $Cpanel::homedir    || q{}; }
    if ( !$abshomedir ) { $abshomedir = $Cpanel::abshomedir || q{}; }
    $dir        =~ s/\n//g;
    $dir        =~ s/\/$//g;
    $abshomedir =~ s/\/$//g;
    my $did_strip_abshomedir = ( $dir =~ s/^$abshomedir// );

    if ( !$did_strip_abshomedir ) {
        $dir =~ s/^$homedir//;
    }

    $dir = "$abshomedir/$dir";
    $dir = _strip_dir_traversal_dots($dir);
    return $dir;
}

sub _strip_dir_traversal_dots {
    my $dir = shift;

    require File::Spec;
    my ( $volume, $directories, $file ) = File::Spec->splitpath($dir);
    my @dirs            = File::Spec->splitdir($directories);
    my @non_parent_dirs = grep { $_ ne '..' } @dirs;              # File::Spec already strips single dots '.'
    my $path            = File::Spec->catdir(@non_parent_dirs);
    $dir = File::Spec->catpath( $volume, $path, $file );

    return $dir;
}

1;
