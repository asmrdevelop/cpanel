package Cpanel::cPCPAN::List;

# cpanel - Cpanel/cPCPAN/List.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## no critic qw(TestingAndDebugging::RequireUseStrict)
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::Version::Full ();
use Cpanel::Logger        ();

our $VERSION = 1.2;
our $TTL     = 7200;    # two hours

my $logger = Cpanel::Logger->new;

# This does not use cpanmetadb.cpanel.net because parsing the YAML causes
# out-of-memory errors.
sub list_available {
    my ( $self, $print ) = @_;

    my $url = 'http://httpupdate.cpanel.net/CPAN/modules/02packages.details.txt';
    require Cpanel::ObjCache;

    my $packages = Cpanel::ObjCache::fetchcachedobj( $url, 'cpan_packages_' . $VERSION, $TTL );

    if ( !$packages || !$packages->{'data'} ) {
        $logger->warn("Cannot download cpan file from url $url");
        return;
    }

    my @ML;
    my $seen_blank = 0;
    my $state      = {
        'printing'  => $print || $self->{'print'},
        'n_printed' => 0,
        'ML'        => \@ML,
    };

    # Try to be as conservative with memory as possible, so avoid split.
    open( my $fh, '<', \$packages->{'data'} ) or return;
    while ( my $line = <$fh> ) {
        chomp $line;

        if ( !$seen_blank ) {
            $seen_blank = 1 if $line =~ /^\s*$/;
            next;
        }

        my $entry = {};
        @{$entry}{qw/modname version path/} = split /\s+/, $line, 3;
        $entry->{'description'} = "$entry->{'modname'} - latest:$entry->{'version'}";

        _list( $entry->{'modname'}, $entry, $state );
    }

    return \@ML;
}

sub search {
    my ( $self, $matcher, $print ) = @_;

    my $printing = $print || $self->{'print'};

    my $version = Cpanel::Version::Full::getversion();

    # no need to uri escape it here, cause the objCache calls does a Cpanel::URL::parse($url)
    my $cpanmeta_url = "http://cpanmetadb.cpanel.net/v1.1/" . ( defined $matcher ? "search?search=$matcher" : 'dump' );

    ( my $filename = $cpanmeta_url ) =~ s/\W/_/g;

    my $cpanmetadb_obj_cache = _fetch_cpan_metadata($cpanmeta_url);

    if ( !$cpanmetadb_obj_cache || !$cpanmetadb_obj_cache->{'data'} ) {
        $logger->warn("Cannot download cpan file from url $cpanmeta_url");
        return;
    }

    my $coderef = _get_yaml_parser_coderef();
    if ( !$coderef ) {
        $logger->warn("Cannot get a YAML parser");
        return;
    }

    $cpanmetadb_obj_cache->{'data'} =~ s/\s*\n/\n/msg;
    my $modinfo_hash = $coderef->( $cpanmetadb_obj_cache->{'data'} );
    if ( !$modinfo_hash ) {
        $logger->warn("Cannot parse YAML");
        return;
    }

    $matcher = '.' unless defined $matcher;

    my @ML;

    my $matcher_regex = qr/$matcher/i;
    my $state         = {
        'printing'  => $printing,
        'n_printed' => 0,
        'ML'        => \@ML,
    };

    for my $result_hr ( @{ $modinfo_hash->{results} } ) {
        for my $modname ( grep { $_ =~ $matcher_regex } keys %$result_hr ) {

            # \Q...\E in the regex would be nice, but /./ has to match any char

            # We have corrected the behavior to show only the packages that
            # have a description, as per Nick K.'s note in case 47321: "Its
            # actually probably an original design flaw to list all the
            # modules, we should only be listing the packages (ones with
            # descriptions)"

            # We used to check to see if there was a description value, however
            # cpanmetadb.cpanel.net only feeds us ones with a description
            _list( $modname, $result_hr->{$modname}, $state );
        }
    }

    return \@ML;
}

sub _list {
    my ( $modname, $data, $state ) = @_;
    my $line = $modname . '=' . ( $data->{'version'} || 'undef' ) . '=' . $data->{'description'};

    if ( $state->{'printing'} ) {
        print "=MODLIST\n" if !$state->{'n_printed'}++;
        print "$line\n";
    }
    else {
        push @{ $state->{'ML'} }, $line;
    }
}

sub _fetch_cpan_metadata {
    my ($url) = @_;

    require Cpanel::ObjCache;

    return Cpanel::ObjCache::fetchcachedobj( $url, 'cpanmetadb_dump_' . $VERSION, $TTL, undef, '/' );
}

#We don't use Cpanel::DataStore here since the YAML module it uses may not be
#installed at the point this code is run.

my $yaml_parser_coderef;

sub _get_yaml_parser_coderef {

    return $yaml_parser_coderef if $yaml_parser_coderef;

    eval { local $SIG{'__DIE__'}; require Cpanel::YAML::Syck; };
    if ($@) {
        eval { local $SIG{'__DIE__'}; require YAML; };
        if ($@) {
            eval { local $SIG{'__DIE__'}; require YAML::Tiny; };
            if ($@) {
                return;
            }
            else {
                no warnings 'once';
                $yaml_parser_coderef = \&YAML::Tiny::Load;
            }
        }
        else {
            no warnings 'once';
            $yaml_parser_coderef = \&YAML::Load;
        }
    }
    else {
        no warnings 'once';
        $yaml_parser_coderef = \&YAML::Syck::Load;
    }

    return $yaml_parser_coderef;
}

1;
