package Cpanel::PHPConfig::CLI;

use Cpanel::SafeRun::Errors ();
use Cpanel::Logger          ();

sub get_php_cli {
    local %ENV = ();
    foreach my $phpbin ( '/usr/local/bin/php', '/usr/bin/php' ) {
        next if !-x $phpbin;
        my $phpout = Cpanel::SafeRun::Errors::saferunallerrors( $phpbin, '-i' );
        if ( $phpout =~ m/(?:\(cli\)|Command\s+Line\s+Interface)/mi ) {
            return $phpbin;
        }
        else {
            Cpanel::Logger::cplog( 'Unexpected output from ' . $phpbin . ' -i while looking for CLI: ' . $phpout, 'warn', __PACKAGE__, 1 );
        }
    }
    return '/usr/local/bin/php';
}

1;
