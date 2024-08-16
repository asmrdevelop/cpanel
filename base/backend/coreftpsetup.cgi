#!/usr/local/cpanel/3rdparty/bin/perl

use Cpanel::SSH::Port    ();
use Cpanel::Encoder::URI ();
my $sshport = Cpanel::SSH::Port::getport();
my $proto;
my ( $domain, $host, $user, $ssl ) = split( /\|/, Cpanel::Encoder::URI::uri_decode_str( $ENV{'QUERY_STRING'} ) );
$ssl = int($ssl);
my $secure    = $ssl ? 'Secure%20' : '';
my $securetxt = $ssl ? 'Secure '   : '';
my $port;

if ($ssl) {
    $port  = $sshport;
    $proto = 'sftp';
}
else {
    $port  = 21;
    $proto = 'ftp';
}
print <<EOM;
Content-Type: application/octet-stream; x-unix-mode=0644; name="${securetxt}$domain.coreftp"
Content-Disposition: attachment; filename="${securetxt}$domain.coreftp"

EOM

my $data = <<EOM;
Type,1
Id,4
PId,0
PASV,2
SSL,0
SSH,$ssl
SSLL,1
SSLX,1
SSLC,0
AdvLst,2
Lgcy,0
Syst,0
Prot,0
SSHp,0
Proxy,0
Alive,2
AliveSecs,15
Cache,2
Recon,2
ARecon,2
XMode,0
CMode,-1
MaxCon,1
Tmout,60
Retries,2
Retry,0
Fldr,0
XRetry,2
XReties,5
RenD,2
RenU,2
Skey,2
NOOP,2
NMDTM,2
NAT,0
PLo,0
PHi,65535
PH,
PU,
PP,
PPt,0
PT,0
PF,0
APE,0
DF,0
CU,0
CL,0
stf,0
nsz,0
n1,0
n2,
n3,0
n4,
n5,
n8,
n7,
f1,
f2,
cr1,
cr2,
n6,
Ex1,
Ex2,
Ex3,
Ex4,
GMT,0
NoUser,0
NoPW,0
OffSt,0
mz1,0
mz2,7
NAA,
Name,$domain
Desc,
Host,$host
User,$user
SvPW,1
HostT,0
PW,
Acct,
PthR,
PthL,
AP,0
Port,$port
Anon,0
RSz,4096
SSz,512
SMax,2000000000
SMin,0
RMax,0
RMin,0
Sc1,
Sc2,
Sx1,
Sx2,
za,0
zb,
EOM

foreach my $line ( split( /\n/, $data ) ) {
    print "$line\r\r\n";
}
print "\1\0\1\0\1";
