package Cpanel::RepoQuery::Apt;

# cpanel - Cpanel/RepoQuery/Apt.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Path::Tiny ();

use Cpanel::Binaries::Debian::AptCache ();
use Cpanel::Binaries::Debian::AptFile  ();

=head1 NAME

Cpanel::RepoQuery::Apt

=head1 SYNOPSIS

See Cpanel::RepoQuery for usage

=head1 DESCRIPTION

Module outlining "what to do" on APT based systems when that's needed within
Cpanel::RepoQuery.

=head1 METHODS

=head2 new

The constructor. Should only be needed by callers who write tests for this.

=cut

sub new ( $class, $opts = undef ) {
    $opts //= {};

    my $self = {%$opts};
    bless $self, $class;

    return $self;
}

=head2 binary_apt_cache

Returns Cpanel::Binaries::Debian::AptCache object or a cached version of this
if it exists.

=cut

sub binary_apt_cache ($self) {

    return $self->{_apt_cache} //= Cpanel::Binaries::Debian::AptCache->new();
}

=head2 binary_apt_file

Returns Cpanel::Binaries::Debian::AptFile object or a cached version of this
if it exists.

=cut

sub binary_apt_file ($self) {

    return $self->{_apt_file} //= Cpanel::Binaries::Debian::AptFile->new();
}

=head2 what_provides($file)

Gets all packages providing $file (from installed repos).
Returns ARRAYREF of package description HASHREFs.

=cut

sub what_provides ( $self, $pkg_or_file, @extra_args ) {    ## no critic qw(Proto Subroutines::ProhibitManyArgs) -- misparse
    my $pkgs_ar = $self->binary_apt_file->what_provides( $pkg_or_file, @extra_args );
    return [ map { $self->binary_apt_cache->show($_) } @$pkgs_ar ];
}

sub _LIST_DIR { return '/var/lib/apt/lists' }

=head2 get_all_packages_from_repo($repo_url)

Gets all packages from the URL given (should be a debian repo URL).
Returns ARRAY of package description HASHREFs.

For those of you playing at home, install ripgrep & parallel then do the
following to get `repoquery` like output:
    apt list 2> /dev/null \
    | cut -d/ -f1 \
    | parallel -n200 apt-cache policy \
    | rg '^(\S+)[\s\S]+?\* (?:\S+\s+){3}(\S+)' -Uor '$1 $2'
See https://askubuntu.com/questions/5976/how-can-i-list-all-packages-ive-installed-from-a-particular-repository#1331065

That said, it's faster for *us* to read the following file:
/var/lib/apt/lists/httpupdate.cpanel.net_ea4-u20-mirrorlist_._Packages

NOTE! Won't return results if you have added a repo yet not ran `apt update`.
This is due to the file above not existing till then.
That said, if sysup is running as part of nightly maintenance,
this will not be a problem for most.

=cut

sub get_all_packages_from_repo ( $self, $repo_url, $mirror_url = undef ) {

    # In the event we get a request for packages from the plugins mirror, the file will be saved as something like:
    # /var/lib/apt/lists/httpupdate.cpanel.net_cpanel-plugins-u20-mirrorlist_._Packages
    # rather than by the IPs we get from the mirror list itself. To correct that, we just override it here.
    # The cached file name is chosen by `apt update` fwiw.
    # The original value comes from https://securedownloads.cpanel.net/cpanel-plugins/cpanel-plugins.list ,
    # however it is also hardcoded in build-tools/repos/cpanel-plugins/0/cpanel-plugins.list for the installer.
    #
    # ZC-11327: Only do this if the host portion is an IP. Otherwise, it breaks using a testing repo. Also,
    # the URL has to change with the version in use.
    #
    # TODO: only IPv4 for now; come back when there are IPv6 mirrors
    if ( $mirror_url && $repo_url =~ m<://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/> && $repo_url =~ m/cpanel\-plugins/ ) {
        $repo_url = $mirror_url;
    }
    my $chopped_url = substr( $repo_url, index( $repo_url, "://" ) + 3 );

    # XXX If there is a literal underscore in the repo URL, apt escapes it as "%5f":
    $chopped_url =~ s/_/%5f/g;
    $chopped_url =~ tr{/}{_};

    # XXX TODO we need to find a way to get the "path" for this repo_url
    # instead of just assuming that ./ is the path (which translates to ._ here)
    # Also note that spaces become _ as well in this file path transformation.

    $chopped_url .= "_._Packages";
    $chopped_url =~ s/\_+/\_/g;

    my $file = _LIST_DIR() . "/" . $chopped_url;

    # Handle the case where apt update creates the cache file with the mirrorlist name rather than the actual repo
    if ( !-f $file ) {
        $file =~ s/\_\.\_Packages/\-mirrorlist\_\.\_Packages/;
    }

    # Using Path::Tiny so we can slurp in the data how we need and avoid wide character print errors
    my @lines = split( /\n/, Path::Tiny::path($file)->slurp_raw() );
    my %pkglist;
    my $cur_pkg;

    # Use this to transform more keys into yum ones to preserve expected API.
    # TODO - check case on what we get in @lines vs what it has at time of copying data into new keys
    my %apt2yum = (
        'pkg'         => 'name',
        'description' => 'summary',
        'longdesc'    => 'description',
        'Homepage'    => 'url',
    );

    foreach my $line (@lines) {
        if ( !$line ) {    # blocks terminate with blank line to separate
            undef $cur_pkg;
            next;
        }

        # First line in block is Package: $pkg_name
        if ( !$cur_pkg ) {
            ($cur_pkg) = $line =~ m/Package: (.*)/;
            die "Packages file $file did not begin with a package!" if !$cur_pkg;
            $pkglist{$cur_pkg} //= { 'pkg' => $cur_pkg };
            next;
        }

        # "Long" description starts with a space on line
        if ( index( $line, " " ) == 0 ) {
            $pkglist{$cur_pkg}->{longdesc} //= '';
            $pkglist{$cur_pkg}->{longdesc} .= $line;
            next;
        }

        # Split version and release for Yum like presentation
        my ( $key, $val ) = $line =~ qr/([A-Za-z0-9]+): (.*)/;
        if ( $key eq 'version' ) {
            @{ $pkglist{$cur_pkg} }{qw{version release}} = split( /-/, $val, 2 );
            next;
        }

        if ( $apt2yum{$key} ) {
            $key = $apt2yum{$key};
        }

        # Set the parameter.
        $pkglist{$cur_pkg}->{ lc($key) } = $val;
        $pkglist{$cur_pkg}->{'name'}    //= $cur_pkg;
        $pkglist{$cur_pkg}->{'summary'} //= $cur_pkg;    # We don't currently have a good field to chose this name from
    }

    # The caller wants list, so map it out that way.
    # Sort it to ensure the ordering.
    return map { $pkglist{$_} } sort( keys(%pkglist) );
}

1;
