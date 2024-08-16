package Cpanel::SafeDir;

# cpanel - Cpanel/SafeDir.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cwd                    ();
use Cpanel::SafeDir::Fixup ();
use Cpanel::SafeDir::MK    ();
use Cpanel::SafeDir::Read  ();
use Cpanel::SafeDir::RM    ();
use Cpanel::SV             ();

*safemkdir = *Cpanel::SafeDir::MK::safemkdir;
*safermdir = *Cpanel::SafeDir::RM::safermdir;
*read_dir  = *Cpanel::SafeDir::Read::read_dir;

my %SAFEDIRCACHE;

our $VERSION = 1.0;

sub safedir {
    my $odir       = shift;
    my $homedir    = shift;
    my $abshomedir = shift;

    $odir = '' if not defined $odir;

    if ( !$homedir )    { $homedir    = $Cpanel::homedir; }
    if ( !$abshomedir ) { $abshomedir = $Cpanel::abshomedir; }
    my $uid = $Cpanel::USERDATA{'uid'} || $>;
    my $dir = $odir;
    if ( length $SAFEDIRCACHE{$uid}{$odir} ) { return $SAFEDIRCACHE{$uid}{$odir}; }

    if ( defined $dir && defined $homedir && $dir eq $homedir || defined $dir && defined $abshomedir && $dir eq $abshomedir ) { return $abshomedir; }

    $dir =~ s/[\r\n]//g;
    $dir = Cpanel::SafeDir::Fixup::homedirfixup( $dir, $homedir, $abshomedir );
    my $testdir = safe_abs_path($dir);

    # If $testdir is false, it means $dir doesn't exist, no further transform needed
    if ($testdir) {

        # If dir had been a symlink make sure it is placed
        # under the home directory
        $dir = Cpanel::SafeDir::Fixup::homedirfixup( $testdir, $homedir, $abshomedir );
    }

    # The resultant path we are to return must under the home
    # directory and must not be a link to somewhere else
    # We initially attempted to resolve any links and make
    # sure the result is under the home directory.
    # But, as pointed out in FogBugz 86861, multiple layers
    # of links can defeat the scheme.  So of the resultant
    # path still contains links we return the home directory
    # rather than potientally go in an endless loop chasing
    # links to links, ad infitinum.
    if ( $dir !~ /^$abshomedir/ or test_path_for_links($dir) ) {

        $dir = $abshomedir;
    }

    $SAFEDIRCACHE{$uid}{$odir} = $dir;
    return $dir;
}

#
# Go through each segment of a path and and test if any portion of it are a link
# Unfortunately, -l <path>, only works if the end segment is a link
# I.e., if <home>/etc is a link to /etc, -l <home>/etc will be true,
# while -l <home>/etc/yum will be false even though it points to /etc/yum
#
sub test_path_for_links {
    my $path = shift;

    my @chunks = split( /\//, $path );

    my $test_path = '';
    foreach my $chunk (@chunks) {
        next unless $chunk;
        $test_path .= '/' . $chunk;

        return 1 if ( -l $test_path );
    }

    return 0;
}

sub safe_abs_path {
    my $path         = shift;
    my $tainted_path = Cwd::abs_path($path);
    return '' unless defined $tainted_path;
    return Cpanel::SV::untaint($tainted_path);    # the regex-capture-as-last-item would return it but lets be explicit for sanity's sake
}

sub clearcache {
    %SAFEDIRCACHE = ();
}

1;

__END__

sub read_dir_with_path {
    my ($dir, $coderef) = @_;
    my @contents = read_dir( $dir ) or return;

    @contents = map { "$dir/$_" } @contents;

    if (defined $coderef) {
        if( ref $coderef eq 'CODE' ) {
            @contents = map { $coderef->( $_ ) ? $_ : () } @contents;
        }
    }

    return wantarray ? @contents : \@contents;
}

sub read_dir_with_abs_path {
    my ($dir, $coderef) = @_;
    my @contents = read_dir_with_path( $dir ) or return;

    @contents = map { todo_abs_path( $_ ) } @contents;

    if (defined $coderef) {
        if( ref $coderef eq 'CODE' ) {
            @contents = map { $coderef->( $_ ) ? $_ : () } @contents;
        }
    }

    return wantarray ? @contents : \@contents;
}

1;
