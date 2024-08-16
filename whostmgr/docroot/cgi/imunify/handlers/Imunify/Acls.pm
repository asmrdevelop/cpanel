package Imunify::Acls;

use Whostmgr::ACLS();

sub checkPermission
{
    if (_isAdmin()
        || (_isReseller()  && _isAvailablePluginForReseller())
    ) {
        return 1;
    }
    return 0;
}

sub _getUser {
    return $ENV{'REMOTE_USER'};
}

sub _isAdmin
{
    if (Whostmgr::ACLS::hasroot()) {
        return 1;
    }
    return 0;
}

sub _isReseller
{
    my $RESELLER_LIST_FILE = '/var/cpanel/resellers';
    my $result = 0;
    if (-e $RESELLER_LIST_FILE) {
        open my $f, $RESELLER_LIST_FILE or die "Could not open $RESELLER_LIST_FILE: $!";

        while( my $line = <$f>)  {
            my @data = split /:/, $line;
            if (_getUser() eq $data[0]) {
                $result = 1;
                last;
            }
        }
        close $f;
    }
    return $result;
}

sub _isAvailablePluginForReseller
{
    if (Whostmgr::ACLS::checkacl('software-imunify360') ) {
        return 1;
    }
    return 0;
}

1;