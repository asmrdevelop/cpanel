package Cpanel::Filesys::Home;

# cpanel - Cpanel/Filesys/Home.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Filesys::Home

=cut

use strict;
use warnings;

use constant _ENOENT => 2;

use Cpanel::StringFunc::Match       ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Filesys::Info           ();
use Cpanel::Filesys::FindParse      ();

=head1 DESCRIPTION

Library for determining the proper home directories in which to deposit freshly created cPanel accounts.

=head1 FUNCTIONS

=head2 getmntpoint

Alias for get_homematch_with_most_free_space.

=cut

*getmntpoint = *get_homematch_with_most_free_space;

=head2 get_all_homedirs

Returns a list of all homedirs suitable for accounts sorted by free space DESC.

Directories are considered suitable if:

=over 4

=item B<HOMEDIR> is set in /etc/wwwacct.conf -- this is used as the home directory if HOMEMATCH is not also set.

=item B<HOMEMATCH> is set in /etc/wwwacct.conf -- all directories matching the pattern provided therein (which are not subdirectories of other matching directories).

=item B</home or /usr/home> is the directory used if neither HOMEMATCH or HOMEDIR is set

=back

=cut

sub get_all_homedirs {
    my ($filesys_ref) = @_;
    my $homedirs      = {};
    my $wwwacct_ref   = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    my $homedir       = $wwwacct_ref->{'HOMEDIR'} || '/home';
    my $homematch     = $wwwacct_ref->{'HOMEMATCH'};

    # Respect disabling HOMEMATCH
    if ( !$homematch ) {
        if ($homedir) {
            return ($homedir);
        }
        else {
            if ( -d '/home' ) {
                return ('/home');
            }
            elsif ( -d '/usr/home' ) {
                return ('/usr/home');
            }
            else {
                mkdir '/home', 0755;
                return ('/home');
            }
        }
    }

    $filesys_ref //= Cpanel::Filesys::Info::_all_filesystem_info();

    # Case CPANEL-27313: When HOMEDIR is set, and /home is not a filesystem
    # mount point, /home would often be neglected as a place one can move
    # accounts to with the Rearrange Account function in WHM.  This will
    # at least ensure /home is available, if it physically exists and is
    # presumed to be on the same filesystem as /.
    if ( -d $homedir && !exists $filesys_ref->{$homedir} ) {
        $homedirs->{$homedir} = $filesys_ref->{'/'}->{'blocks_free'};
    }

    # Eject all mount points which are not read/writable
    foreach my $mp ( keys %$filesys_ref ) {
        my @modes = split( /,/, $filesys_ref->{$mp}{_mode} );
        if ( !grep { $_ eq 'rw' } @modes ) {
            delete $filesys_ref->{$mp};
            next;
        }

        # The way to test this is to make a bogus disk using dmsetup (the zero, error or delay targets)
        # For our purposes, a quick symlink read/write test should at least prevent using entirely siezed up disks.
        require Cpanel::UUID;
        my $link_test_file = Cpanel::UUID::random_uuid();
        unlink("$mp/$link_test_file");    #If this fails, we'll just fail to write the symlink, so who cares
        require Cpanel::Autodie;
        if ( !eval { Cpanel::Autodie::symlink( "yes", "$mp/$link_test_file" ) } ) {
            delete $filesys_ref->{$mp};
            next;
        }

        require Cpanel::Autodie;
        if ( !eval { Cpanel::Autodie::readlink("$mp/$link_test_file") } ) {
            delete $filesys_ref->{$mp};
            next;
        }
        unlink("$mp/$link_test_file") or do {
            warn "Symlink “$mp/$link_test_file” left in place! ($!)" unless $! == _ENOENT();
        };
    }

    foreach my $disk ( sort keys %{$filesys_ref} ) {    # sorting will put /dev before and nullfs mounts

        if ( $disk !~ m/$homematch/ and Cpanel::StringFunc::Match::beginmatch( $homedir, $disk ) and $disk eq Cpanel::Filesys::FindParse::find_mount( $filesys_ref, $homedir ) ) {
            $homedirs->{$homedir} = $filesys_ref->{$disk}{'blocks_free'};
        }
        elsif ( $disk !~ m/$homematch/ ) {
            next;
        }
        else {
            if ( $disk eq '/' ) {

                # This could conceivably happen if homematch was / for some odd reason
                if ( !exists $homedirs->{$homedir} ) {
                    $homedirs->{$homedir} = $filesys_ref->{$disk}->{'blocks_free'};
                }
            }
            else {
                $homedirs->{$disk} = $filesys_ref->{$disk}->{'blocks_free'};
            }
        }
    }

    # Eject any home directory which is a sub directory of another home directory.
    # This will prevent user FUSE mounts in their homes from being used, which may be larger than our home partition.
    my @candidates = keys(%$homedirs);
    foreach my $hd (@candidates) {
        my @dupes = grep {
            my $subj     = $_;
            my $subj_adj = $subj;
            my $lastchar = length($subj) - 1;

            #Handle missing trailing slashes
            $subj_adj = "$subj/" unless index( $subj, '/', $lastchar ) == $lastchar;
            $hd =~ m/^\Q$subj_adj\E/ && $subj ne $hd
        } @candidates;
        delete $homedirs->{$hd} if @dupes;
    }

    if ( scalar keys %$homedirs ) {
        my @ret = sort { $homedirs->{$b} <=> $homedirs->{$a} } keys %$homedirs;
        return @ret;
    }

    return ($homedir);
}

=head2 get_homematch_with_most_free_space

Returns the home directory with the most free space available.

In practice this is what is used to find the directory to deposit new accounts
into.

=cut

sub get_homematch_with_most_free_space {
    my @homedirs = get_all_homedirs();
    my $best     = $homedirs[0];
    $best =~ s/\/$//g;
    return $best;
}

1;

__END__
