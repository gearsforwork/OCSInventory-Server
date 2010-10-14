###############################################################################
## OCSINVENTORY-NG 
## Copyleft Pascal DANEK 2008
## Web : http://www.ocsinventory-ng.org
##
## This code is open source and may be copied and modified as long as the source
## code is always made freely available.
## Please refer to the General Public Licence http://www.gnu.org/ or Licence.txt
################################################################################
package Apache::Ocsinventory::Server::Capacities::Snmp::Inventory;

use strict;

require Exporter;

our @ISA = qw /Exporter/;

our @EXPORT = qw / _snmp_inventory /;

use Apache::Ocsinventory::Server::System qw / :server /;
use Apache::Ocsinventory::Server::Capacities::Snmp::Data;

sub _snmp_context {
  my $snmpDeviceId = shift;
  my $request;
  my $snmpDatabaseId;
  my $snmpContext = {};

  my $dbh = $Apache::Ocsinventory::CURRENT_CONTEXT{'DBI_HANDLE'};

  # Retrieve Device if exists
  $request = $dbh->prepare('SELECT ID,ID FROM snmp WHERE SNMPDEVICEID=?' );

  #TODO:retrieve the unless here like standard Inventory.pm
  $request->execute($snmpDeviceId);

  if($request->rows){
    my $row = $request->fetchrow_hashref;
    $snmpContext->{DATABASE_ID} = $row->{'ID'};
    $snmpContext->{EXIST_FL} = 1;
  } else {
    $dbh->do('INSERT INTO snmp(SNMPDEVICEID) VALUES(?)', {}, $snmpDeviceId);
    $request = $dbh->prepare('SELECT ID FROM snmp WHERE SNMPDEVICEID=?');
    unless($request->execute($snmpDeviceId)){
      &_log(518,'snmp','id_error') if $ENV{'OCS_OPT_LOGLEVEL'};
      return(1);
    }
    my $row = $request->fetchrow_hashref;
    $snmpContext->{DATABASE_ID} = $row->{'ID'};
  }
  
  return($snmpContext);
}


sub _snmp_inventory{
  my ( $sectionsMeta, $sectionsList ) = @_;
  my $section;
  
  my $result = $Apache::Ocsinventory::CURRENT_CONTEXT{'XML_ENTRY'}; 
  my $snmp_devices = $result->{CONTENT}->{DEVICE};
  
  #Getting data for the several snmp devices that we have in the xml
  for( @$snmp_devices ){
    my $snmpDeviceXml=$_;

    #Getting context and ID in the snmp table for this device
    my $snmpContext = &_snmp_context($snmpDeviceXml->{COMMON}->{SNMPDEVICEID});
    my $snmpDatabaseId =  $snmpContext->{DATABASE_ID};

    #Call COMMON section update
    if(&_snmp_common($snmpDeviceXml->{COMMON},$snmpDatabaseId)) {
      return 1;
    }

    # Call the _update_snmp_inventory_section for each section
    for $section (@{$sectionsList}){
      if(_update_snmp_inventory_section($snmpDeviceXml, $snmpContext, $section, $sectionsMeta->{$section})){
        return 1;
      }
    }
  }
}

sub _update_snmp_inventory_section{
  my ($snmpDeviceXml, $snmpContext, $section, $sectionMeta) = @_;

  my $snmpDatabaseId = $snmpContext->{DATABASE_ID};
  my $dbh = $Apache::Ocsinventory::CURRENT_CONTEXT{'DBI_HANDLE'};

  my @bind_values;

  #TODO: enhance this part to prevent from deleting data everytime before rewrtting it and to prevent a bug if one (or more) of the snmp tables has no SNMP_ID field)
  #We delete related data for this device if already exists	
  if ($snmpContext->{EXIST_FL})  {
    if(!$dbh->do("DELETE FROM $section WHERE SNMP_ID=?", {}, $snmpDatabaseId)){
        return(1);
    }
  }

  # Processing values	
  my $sth = $dbh->prepare( $sectionMeta->{sql_insert_string} );

  #We delete the snmp_ pattern to be in concordance with XML
  my $XmlSection = $section;
  $XmlSection =~ s/snmp_//g;

  my $refXml = $snmpDeviceXml->{uc $XmlSection};
  
  # Multi lines (forceArray)
  if($sectionMeta->{multi}){
    for my $line (@$refXml){
      &_get_snmp_bind_values($line, $sectionMeta, \@bind_values);

      if(!$sth->execute($snmpDatabaseId, @bind_values)){
        return(1);
      }
      @bind_values = ();
    }
  }
  # One line (hash)
  else{
    &_get_snmp_bind_values($refXml, $sectionMeta, \@bind_values);
    if( !$sth->execute($snmpDatabaseId, @bind_values) ){
      return(1);
    }
  }

  $dbh->commit;
  0;
}


sub _snmp_common{
  my $base= shift;
  my $snmpDatabaseId = shift;
  my $dbh = $Apache::Ocsinventory::CURRENT_CONTEXT{'DBI_HANDLE'};

 #Store the COMMON data from XML
 $dbh->do("UPDATE snmp SET IPADDR=".$dbh->quote($base->{IPADDR}).", 
  LASTDATE=NOW(),
  MACADDR=".$dbh->quote($base->{MACADDR}).",
  SNMPDEVICEID=".$dbh->quote($base->{SNMPDEVICEID}).",
  NAME=".$dbh->quote($base->{NAME}).",
  DESCRIPTION=".$dbh->quote($base->{DESCRIPTION}).",
  CONTACT=".$dbh->quote($base->{CONTACT}).",
  LOCATION=".$dbh->quote($base->{LOCATION}).",
  UPTIME=".$dbh->quote($base->{UPTIME}).",
  DOMAIN=".$dbh->quote($base->{DOMAIN}).",
  TYPE=".$dbh->quote($base->{TYPE})."
   WHERE ID = $snmpDatabaseId")
  or return(1);
 
  $dbh->commit;
  0;
}

1;