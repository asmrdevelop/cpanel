<?php

# cpanel - Cpanel/Accounting-class.php.inc         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Updated and turned into a class on 9/23/02 by Michael Nix  michael@hostevolve.com

class accounting
{
    // set global variables here
    var $cpanelaccterr;
    var $host;
    var $user;
    var $accesshash;
    var $usessl;

    function suspend($suspenduser)
    {
        $suspenduser = urlencode($suspenduser);
        $result = $this->whmreq("/scripts/remote_suspend?user=${suspenduser}");
        if ($this->cpanelaccterr != "") { return $this->cpanelaccterr; }
        return $result;
    } // End function suspend()

    function unsuspend($suspenduser)
    {
        $suspenduser = urlencode($suspenduser);
        $result = $this->whmreq("/scripts/remote_unsuspend?user=${suspenduser}");
        if ($this->cpanelaccterr != "") { return $this->cpanelaccterr; }
        return $result;
    } // End function unsuspend()

    function killacct ($killuser)
    {
        $suspenduser = urlencode($killuser);
        $result = $this->whmreq("/scripts/killacct?user=${killuser}&nohtml=1");
        if ($this->cpanelaccterr != "") { return $this->cpanelaccterr; }
        return $result;
    } // End function killacct()

    function showversion ()
    {
        $result = $this->whmreq("/scripts2/showversion");
        if ($this->cpanelaccterr != "") { return $this->cpanelaccterr; }
        return $result;
    } // End function showversion()

    function createacct ($acctdomain,$acctuser,$acctpass,$acctplan)
    {
        $acctdomain = urlencode($acctdomain);
        $acctuser = urlencode($acctuser);
        $acctpass = urlencode($acctpass);
        $acctplan = urlencode($acctplan);
        $result = $this->whmreq("/scripts/wwwacct?remote=1&nohtml=1&username=${acctuser}&password=${acctpass}&domain=${acctdomain}&plan=${acctplan}");
        if ($this->cpanelaccterr != "") { return $this->cpanelaccterr; }
        return $result;
    } // End function createacct()

    function listaccts ()
    {
        $result = $this->whmreq("/scripts2/listaccts?nohtml=1&viewall=1");
        if ($this->cpanelaccterr != "") { return $this->cpanelaccterr; }
        $page = split("\n",$result);
        foreach ($page as $line)
        {
            list($acct,$contents) = split("=", $line);
            if ($acct != "")
            {
                $allc = split(",", $contents);
                $accts[$acct] = $allc;
            }
        }
        return($accts);
    } // End function listaccts()

    function listpkgs ()
    {
        $result = $this->whmreq("/scripts/remote_listpkg");
        if ($this->cpanelaccterr != "") { return $this->cpanelaccterr; }
        $page = split("\n",$result);
        foreach ($page as $line)
        {
            list($pkg,$contents) = split("=", $line);
            if ($pkg != "")
            {
                $allc = split(",", $contents);
                $pkgs[$pkg] = $allc;
            }
        }
        return($pkgs);
    } // End function listpkgs()

    function whmreq ($request)
    {
        $cleanaccesshash = preg_replace("'(\r|\n)'","",$this->accesshash);
        $authstr = $this->user . ":" . $cleanaccesshash;
        $this->cpanelaccterr = "";
        if (function_exists("curl_init"))
        {
            $ch = curl_init();
            if ($this->usessl)
            {
                curl_setopt($ch, CURLOPT_SSL_VERIFYPEER,0);
                curl_setopt($ch, CURLOPT_SSL_VERIFYHOST,0);
                curl_setopt($ch, CURLOPT_URL, "https://$this->host:2087" . $request);
            }
            else
            {
                curl_setopt($ch, CURLOPT_URL, "http://$this->host:2086" . $request);
            }
            curl_setopt($ch, CURLOPT_HEADER, 0);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER,1);
            $curlheaders[0] = "Authorization: WHM $authstr";
            curl_setopt($ch,CURLOPT_HTTPHEADER,$curlheaders);
            $data=curl_exec ($ch);
            curl_close ($ch);
        }
        elseif(function_exists("socket_create"))
        {
            if ($this->usessl)
            {
                $this->cpanelaccterr = "SSL Support requires curl";
                return;
            }
            $service_port = 2086;
            $address = gethostbyname($this->host);
            $socket = socket_create (AF_INET, SOCK_STREAM, 0);
            if ($socket < 0)
            {
                $this->cpanelaccterr = "socket_create() failed";
                return;
            }
            $result = socket_connect ($socket, $address, $service_port);
            if ($result < 0)
            {
                $this->cpanelaccterr = "socket_connect() failed";
                return;
            }
            $in = "GET $request HTTP/1.0\n";
            socket_write($socket,$in,strlen($in));
            $in = "Connection: close\n";
            socket_write($socket,$in,strlen($in));
            $in = "Authorization: WHM $authstr\n\n\n";
            socket_write($socket,$in,strlen($in));
            $inheader = 1;
            while(($buf = socket_read($socket, 512)) != false)
            {
                if (!$inheader)
                {
                    $data .= $buf;
                }
                if(preg_match("'\r\n\r\n$'s", $buf))
                {
                    $inheader = 0;
                }
                if(preg_match("'\n\n$'s", $buf))
                {
                    $inheader = 0;
                }
            }
        }
        else
        {
            $this->cpanelaccterr = "php not compiled with --enable-sockets OR curl";
            return;
        }
        return $data;
    } // End function whmreq()
} // End class accounting

?>
