CREATE PROC [ME_Stage].[sp_DynamicODSLoad] @DatasetID [INT] AS
BEGIN
	/*DEBUG
	declare @DatasetID [INT],@PARTITIONSTRING [VARCHAR](100)

		SET @DatasetID=53
*/
	/*DECLARE GLOBALS*/
	DECLARE @SOURCESCHEMA_STG VARCHAR(100)
	
		,@HasDelta INT
		,@HasBusinessKey INT
		,@EntityID BIGINT
		,@TARGETSCHEMA_ODS VARCHAR(MAX)
		,@TARGETTBL_ODS VARCHAR(MAX)
		,@SOURCEVW_STG VARCHAR(MAX)
		,@ODSEXISTS int 
		,@ODSSQL VARCHAR(MAX)
		,@VWDROP varchar(max)
	
	/*SET GLOBAL PARAMETERS*/
	SET @SOURCESCHEMA_STG = (SELECT TOP 1 AttributeValue	FROM ME_Config.GLOBALS WHERE [Attribute]='STAGE_SCHEMA')
	SET @EntityID = (SELECT id from Metadata.Entity where DatasetID=@DatasetID)
	SET @HasBusinessKey = (SELECT COUNT(1) FROM Metadata.Attribute where entityid=@EntityID and [KEY]='EntityRowIdentifier' )

	
    

		SET @SOURCEVW_STG =	(SELECT TOP 1 '['+@SOURCESCHEMA_STG+'].[vw_' + ConnectionName + '_' + e.SchemaName + '_' + e.Name + ']' 
								FROM METADATA.Entity E  INNER JOIN ME_Config.Dataset D ON D.ID=E.DatasetID
								INNER JOIN ME_Config.Connection C ON C.id=D.ConnectionID
								WHERE e.id=@EntityID
							)
		SET @TARGETSCHEMA_ODS = (SELECT TOP 1 ConnectionName + '_' + e.SchemaName 
								FROM METADATA.Entity E  INNER JOIN ME_Config.Dataset D ON D.ID=E.DatasetID
								INNER JOIN ME_Config.Connection C ON C.id=D.ConnectionID
								WHERE e.id=@EntityID)

		SET @TARGETTBL_ODS = (SELECT TOP 1 e.[name] FROM METADATA.Entity E 	WHERE e.id=@EntityID)

		SET @ODSEXISTS= (SELECT COUNT(1) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' AND TABLE_SCHEMA=@TARGETSCHEMA_ODS AND TABLE_NAME=@TARGETTBL_ODS)

	
	SET @ODSSQL =(SELECT 
	'BEGIN TRY DROP TABLE  ['+@TARGETSCHEMA_ODS+'].['+@TARGETTBL_ODS+'_new] END TRY
	 BEGIN CATCH PRINT 1 END CATCH
	
	CREATE TABLE ['+@TARGETSCHEMA_ODS+'].['+@TARGETTBL_ODS+'_new]
	 WITH
			(
			DISTRIBUTION = ROUND_ROBIN,
			CLUSTERED COLUMNSTORE INDEX
	  		
			)
	AS

	SELECT * FROM '+@SOURCEVW_STG+' 
	'+CASE WHEN @HasBusinessKey>0 AND @ODSEXISTS>0 then '
	UNION ALL
	SELECT * FROM ['+@TARGETSCHEMA_ODS+'].['+@TARGETTBL_ODS+'] WITH (NOLOCK)
	WHERE BusinessKeyHash_id NOT IN (SELECT BusinessKeyHash_id FROM '+@SOURCEVW_STG+');
    RENAME OBJECT ['+@TARGETSCHEMA_ODS+'].['+@TARGETTBL_ODS+'] TO ['+@TARGETTBL_ODS+'_OLD];
	RENAME OBJECT ['+@TARGETSCHEMA_ODS+'].['+@TARGETTBL_ODS+'_new] TO ['+@TARGETTBL_ODS+'];
	DROP TABLE ['+@TARGETSCHEMA_ODS+'].['+@TARGETTBL_ODS+'_OLD]
	DROP TABLE ['+@SOURCESCHEMA_STG+'].['+@TARGETSCHEMA_ODS+'_'+@TARGETTBL_ODS+'];' 
	 WHEN @HasBusinessKey <= 1 AND @ODSEXISTS>0 then '
	RENAME OBJECT ['+@TARGETSCHEMA_ODS+'].['+@TARGETTBL_ODS+'] TO ['+@TARGETTBL_ODS+'_OLD];
	RENAME OBJECT ['+@TARGETSCHEMA_ODS+'].['+@TARGETTBL_ODS+'_new] TO ['+@TARGETTBL_ODS+'];
	DROP TABLE ['+@TARGETSCHEMA_ODS+'].['+@TARGETTBL_ODS+'_OLD]
	DROP TABLE ['+@SOURCESCHEMA_STG+'].['+@TARGETSCHEMA_ODS+'_'+@TARGETTBL_ODS+'];' 
	ELSE '
	RENAME OBJECT ['+@TARGETSCHEMA_ODS+'].['+@TARGETTBL_ODS+'_new] TO ['+@TARGETTBL_ODS+'];
	DROP TABLE ['+@SOURCESCHEMA_STG+'].['+@TARGETSCHEMA_ODS+'_'+@TARGETTBL_ODS+'];'  
	 END)
    
	SET @VWDROP = 'BEGIN TRY DROP VIEW '+@SOURCEVW_STG+' END TRY  BEGIN CATCH PRINT 2 END CATCH'


	PRINT @ODSSQL
	PRINT @VWDROP
	
	EXEC (@ODSSQL)
	EXEC (@VWDROP)
	

END