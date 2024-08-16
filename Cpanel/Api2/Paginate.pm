package Cpanel::Api2::Paginate;

# cpanel - Cpanel/Api2/Paginate.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Math ();

our $DEFAULT_PAGE_SIZE = 100;

our %cpvar_to_state = qw(
  api2_paginate_start     start_result
  currentpage             current_page
  pages                   total_pages
  api2_paginate_size      results_per_page
  api2_paginate_total     total_results
);

sub get_state {
    return { map { ( $cpvar_to_state{$_} => $Cpanel::CPVAR{$_} ) } keys %cpvar_to_state };
}

sub setup_pagination_vars {
    my $rCFG  = shift;
    my $rDATA = shift;

    return if !$rCFG->{'api2_paginate'};

    if ( !$rCFG->{'api2_paginate_start'} || $rCFG->{'api2_paginate_start'} < 1 ) {
        $rCFG->{'api2_paginate_start'} = 1;
    }
    if ( !defined $rCFG->{'api2_paginate_size'} || !int $rCFG->{'api2_paginate_size'} ) {
        $rCFG->{'api2_paginate_size'} = $DEFAULT_PAGE_SIZE;
    }

    my $begin_chop  = ( $rCFG->{'api2_paginate_start'} - 1 );
    my $end_chop    = ( $rCFG->{'api2_paginate_start'} + $rCFG->{'api2_paginate_size'} - 1 );
    my $currentpage = Cpanel::Math::ceil( $rCFG->{'api2_paginate_start'} / $rCFG->{'api2_paginate_size'} );
    my $pages       = Cpanel::Math::ceil( ( scalar @$rDATA ) / $rCFG->{'api2_paginate_size'} );

    $Cpanel::CPVAR{'api2_paginate_start'}    = $rCFG->{'api2_paginate_start'};
    $Cpanel::CPVAR{'api2_paginate_size'}     = $rCFG->{'api2_paginate_size'};
    $Cpanel::CPVAR{'api2_paginate_previous'} = $rCFG->{'api2_paginate_start'} - $rCFG->{'api2_paginate_size'};
    if ( $Cpanel::CPVAR{'api2_paginate_previous'} < 1 ) {
        $Cpanel::CPVAR{'api2_paginate_previous'} = 1;
    }
    $Cpanel::CPVAR{'api2_paginate_end'}      = $end_chop;
    $Cpanel::CPVAR{'api2_paginate_end_next'} = ( $end_chop + 1 );
    $Cpanel::CPVAR{'api2_paginate_total'}    = scalar @$rDATA;
    $Cpanel::CPVAR{'currentpage'}            = $currentpage;
    $Cpanel::CPVAR{'pages'}                  = $pages;
    $Cpanel::CPVAR{'wantnext'}               = ( $currentpage + 1 );
    $Cpanel::CPVAR{'wantprev'}               = ( $currentpage - 1 );
    if ( $Cpanel::CPVAR{'wantprev'} < 0 )      { $Cpanel::CPVAR{'wantprev'} = 0; }
    if ( $Cpanel::CPVAR{'wantnext'} > $pages ) { $Cpanel::CPVAR{'wantprev'} = $pages; }

    # no need to splice the end off since it will just get ignored any ways and its a waste of cpu time
    #splice ( @{$rDATA}, $end_chop );

    if ($begin_chop) {
        splice( @{$rDATA}, 0, $begin_chop );
    }

    return ( $begin_chop, $end_chop );
}
1;
