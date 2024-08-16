package Whostmgr::HTMLInterface::Elements;

use Cpanel::Math ();

sub _gen_progress_bar {
    my %OPTS = @_;

    if ( $OPTS{'limit'} > 0 && $OPTS{'current'} < $OPTS{'limit'} ) {
        return int Cpanel::Math::roundto( ( ( $OPTS{'current'} / $OPTS{'limit'} ) * 100 ), 10, 100 );
    }
    else {
        if ( $OPTS{'current'} >= $OPTS{'limit'} ) {
            return 100;
        }
        else {
            return 0;
        }
    }
}

1;
