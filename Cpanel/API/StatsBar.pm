package Cpanel::API::StatsBar;

# cpanel - Cpanel/API/StatsBar.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic(TestingAndDebugging::RequireUseWarnings) -- This is older code and has not been tested for warnings safety yet.

use Cpanel                ();
use Cpanel::LoadModule    ();
use Cpanel::Locale        ();
use Cpanel::Debug         ();
use Cpanel::ExpVar        ();
use Cpanel::ExpVar::Utils ();
use Cpanel::Math          ();
use Cpanel::StatsBar      ();

# Called from WHM API v1 “uapi_cpanel”. May potentially
# need to be refactored.
*_clear_cache = *Cpanel::StatsBar::clear_cache;

my $locale;
my $ONE_MEGABYTE = ( 1024**2 );

sub get_stats {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $args, $result ) = @_;
    my ( $display, $warnings, $warninglevel, $warnout, $infinityimg, $infinitylang, $rowcounter, $needshash, $format_bytes ) = $args->get(qw(display warnings warninglevel warnout infinityimg infinitylang rowcounter needshash format_bytes));

    $locale ||= Cpanel::Locale::lh();    # no args uses $Cpanel::CPDATA{'LANG'};
    if ( !$Cpanel::StatsBar::rSTATS ) {
        Cpanel::StatsBar::_load_stats_ref();
    }
    my $rSTATS = $Cpanel::StatsBar::rSTATS;    ## for aliasing only

    my @RSD;
    foreach my $stat (
        grep {

            # if we do not know about the stat skip it
            exists $rSTATS->{$_} &&

              # if we have a required role check to make sure we have this role
              ( !defined $rSTATS->{$_}{'role'} || _has_role( $rSTATS->{$_}{'role'} ) ) &&

              # if we have a required feature tag check to make sure we have this feature
              ( !defined( $rSTATS->{$_}{'feature'} ) || Cpanel::hasfeature( $rSTATS->{$_}{'feature'} ) )

        } ( split /\|/, $display )
    ) {
        foreach my $item ( grep { exists $rSTATS->{$stat}{$_} } ( 'condition', 'value', '_max', '_count' ) ) {
            if ( ref $rSTATS->{$stat}{$item} eq 'CODE' ) {
                Cpanel::LoadModule::loadmodule( $rSTATS->{$stat}{'module'} ) if exists $rSTATS->{$stat}{'module'};
                eval { $rSTATS->{$stat}{$item} = $rSTATS->{$stat}{$item}->(); };
                if ($@) {
                    warn;
                    warn "Failed to fetch stat item: $stat:$item";

                    # Set the stat to undef as JSON cannot serialize coderefs
                    $rSTATS->{$stat}{$item} = undef;
                    next;
                }
            }
            elsif ( length $rSTATS->{$stat}{$item} && rindex( $rSTATS->{$stat}{$item}, 'expvar:', 0 ) == 0 ) {
                my $sub = $rSTATS->{$stat}{$item};
                $sub =~ s/^expvar://;
                $Cpanel::Debug::level > 5 && print STDERR "StatsBar::api2_stat calling $sub\n";
                $rSTATS->{$stat}{$item} =
                    ( $sub eq '!$hasdedicatedip' ) ? ( Cpanel::ExpVar::Utils::hasdedicatedip() ? 0 : 1 )
                  : ( $sub eq '$hasdedicatedip' )  ? Cpanel::ExpVar::Utils::hasdedicatedip()
                  : ( $sub eq '$ip' )              ? Cpanel::ExpVar::Utils::get_public_ip()
                  : ( $sub eq '$haspostgres' )     ? Cpanel::ExpVar::Utils::haspostgres()
                  :                                  Cpanel::ExpVar::expvar( $sub, 0, 1 );
            }
            if ( $item eq '_max' ) {
                if ( !defined( $rSTATS->{$stat}{'_max'} ) || $rSTATS->{$stat}{'_max'} eq '0' || $rSTATS->{$stat}{'_max'} eq '0.00' ) {
                    if ( $rSTATS->{$stat}{'zeroisunlimited'} ) {
                        $rSTATS->{$stat}{$item} = 'unlimited';
                    }
                    else {
                        $rSTATS->{$stat}{$item} = 0;
                    }
                }
                elsif ( $rSTATS->{$stat}{'_max'} =~ m/unlimited/i ) {
                    $rSTATS->{$stat}{'_max'} = 'unlimited';
                }
            }
        }
        next if ( defined( $rSTATS->{$stat}{'condition'} ) && !int( $rSTATS->{$stat}{'condition'} ) );

        my $count = $rSTATS->{$stat}{'_count'} && $rSTATS->{$stat}{'_count'} =~ qr{^[-+]?[0-9\.]+$} ? $rSTATS->{$stat}{'_count'} : 0;
        my $max   = $rSTATS->{$stat}{'_max'}   && $rSTATS->{$stat}{'_max'}   =~ qr{^[-+]?[0-9\.]+$} ? $rSTATS->{$stat}{'_max'}   : 0;

        if ( defined $rSTATS->{$stat}{'_max'} && $rSTATS->{$stat}{'_max'} eq 'unlimited' ) {
            $rSTATS->{$stat}{'percent'} = 0;
        }
        elsif ( $count > $max ) {
            $rSTATS->{$stat}{'percent'} = 100;
        }
        else {
            $rSTATS->{$stat}{'percent'} =
              $max > 0
              ? Cpanel::Math::roundto( ( ( $count / $max ) * 100 ), 1, 100 )
              : 0;
        }

        if (   ( defined($warnings) && $rSTATS->{$stat}{'percent'} < $warninglevel )
            || ( defined($warnout) && $warnout eq '0' && $rSTATS->{$stat}{'percent'} eq '100' ) ) {
            next;
        }

        @{ $rSTATS->{$stat} }{ 'percent5', 'percent10', 'percent20', 'max', 'count', 'item', 'name', 'id' } = (
            ( $max > 0 ? Cpanel::Math::roundto( ( ( $count / $max ) * 100 ), 5,  100 ) : 0 ),
            ( $max > 0 ? Cpanel::Math::roundto( ( ( $count / $max ) * 100 ), 10, 100 ) : 0 ),
            ( $max > 0 ? Cpanel::Math::roundto( ( ( $count / $max ) * 100 ), 20, 100 ) : 0 ),
            $rSTATS->{$stat}{'_max'},
            $rSTATS->{$stat}{'_count'},
            (
                exists $rSTATS->{$stat}{'phrase'}
                ? $locale->makevar( $rSTATS->{$stat}{'phrase'} )    # TODO: CPANEL-3506: Use make_text on the original phrases, so we don't need to makevar.
                : $stat
            ),
            $stat,
            $stat
        );

        if ( $max > 0 && $count >= $max ) {
            $rSTATS->{$stat}{'is_maxed'} = $rSTATS->{$stat}{'_maxed'} = 1;
            $Cpanel::CPVAR{ 'statsbar_' . $stat . '_maxed' } = 1;
        }
        else {
            $rSTATS->{$stat}{'is_maxed'} = $rSTATS->{$stat}{'_maxed'} = 0;
            $Cpanel::CPVAR{ 'statsbar_' . $stat . '_maxed' } = 0;
        }

        if ( $rSTATS->{$stat}{'units'} ) {
            my $should_format_bytes = ( $format_bytes || $rSTATS->{$stat}{'normalized'} || $stat =~ m{bandwidthusage} ) ? 1 : 0;
            if ( defined $rSTATS->{$stat}{'_max'} && $rSTATS->{$stat}{'_max'} =~ m/^[-+]?[0-9\.]+$/ ) {

                my $max_in_bytes =
                    ( $rSTATS->{$stat}{'units'} eq 'MB' && $rSTATS->{$stat}{'normalized'} )
                  ? ( $rSTATS->{$stat}{'_max'} * $ONE_MEGABYTE )
                  : $rSTATS->{$stat}{'_max'};

                $rSTATS->{$stat}{'max'} =
                    $should_format_bytes              ? $locale->format_bytes($max_in_bytes)
                  : $rSTATS->{$stat}{'units'} eq 'MB' ? $locale->numf( $max_in_bytes / $ONE_MEGABYTE, 2 )
                  :                                     $locale->numf( $max_in_bytes, 2 );
            }
            if ( defined $rSTATS->{$stat}{'_count'} && $rSTATS->{$stat}{'_count'} =~ m/^[-+]?[0-9\.]+$/ ) {
                my $count_in_bytes =
                    ( $rSTATS->{$stat}{'units'} eq 'MB' && $rSTATS->{$stat}{'normalized'} )
                  ? ( $rSTATS->{$stat}{'_count'} * $ONE_MEGABYTE )
                  : $rSTATS->{$stat}{'_count'};
                $rSTATS->{$stat}{'count'} =
                    $should_format_bytes              ? $locale->format_bytes($count_in_bytes)
                  : $rSTATS->{$stat}{'units'} eq 'MB' ? $locale->numf( $count_in_bytes / $ONE_MEGABYTE, 2 )
                  :                                     $locale->numf( $count_in_bytes, 2 );
            }
        }
        else {
            if ( defined $rSTATS->{$stat}{'_max'} ) {
                $rSTATS->{$stat}{'max'} = $rSTATS->{$stat}{'_max'} =~ m/^[-+]?[0-9\.]+$/ ? $locale->numf( $rSTATS->{$stat}{'_max'} ) : $rSTATS->{$stat}{'_max'};
            }
            if ( defined $rSTATS->{$stat}{'_count'} ) {
                $rSTATS->{$stat}{'count'} = $rSTATS->{$stat}{'_count'} =~ m/^[-+]?[0-9\.]+$/ ? $locale->numf( $rSTATS->{$stat}{'_count'} ) : $rSTATS->{$stat}{'_count'};
            }
        }

        if ($infinityimg) {
            if ( $rSTATS->{$stat}{'_max'} && $rSTATS->{$stat}{'_max'} =~ m/unlimited/i ) {
                $rSTATS->{$stat}{'max'} = '<img src="' . $infinityimg . '" alt="" border="0" />';
            }
            if ( defined $rSTATS->{$stat}{'_count'} && $rSTATS->{$stat}{'_count'} =~ m/unlimited/i ) {
                $rSTATS->{$stat}{'count'} = '<img src="' . $infinityimg . '" alt="" border="0" />';
            }
        }
        elsif ($infinitylang) {
            if ( $rSTATS->{$stat}{'_max'} =~ m/unlimited/i ) {
                $rSTATS->{$stat}{'max'} = '∞';
            }
            if ( $rSTATS->{$stat}{'_count'} =~ m/unlimited/i ) {
                $rSTATS->{$stat}{'count'} = '∞';
            }
        }

        $rSTATS->{$stat}{'max'} = '' if !defined $rSTATS->{$stat}{'max'};
        $rSTATS->{$stat}{'max'}   =~ s/\s+$//g;
        $rSTATS->{$stat}{'count'} =~ s/\s+$//g if defined $rSTATS->{$stat}{'count'};

        $rSTATS->{$stat}{'rowtype'} = ( ++$Cpanel::StatsBar::ROWCOUNTERS{$rowcounter} % 2 == 0 ? 'odd' : 'even' ) if $rowcounter;

        push @RSD, $rSTATS->{$stat};
    }

    if ($needshash) {
        my %RSD_hash = map { $_->{id} => $_ } @RSD;
        $result->data( \%RSD_hash );
    }
    else {
        $result->data( \@RSD );
    }

    return 1;
}

my %_role_cache;

sub _has_role {
    my ($role) = @_;
    require Cpanel::Server::Type::Profile::Roles;
    return $_role_cache{$role} //= Cpanel::Server::Type::Profile::Roles::are_roles_enabled($role);
}

our %API = (
    get_stats => { allow_demo => 1 },
);

1;
