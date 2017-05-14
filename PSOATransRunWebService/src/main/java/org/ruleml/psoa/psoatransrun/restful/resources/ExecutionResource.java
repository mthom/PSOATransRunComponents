package org.ruleml.psoa.psoatransrun.restful.resources;

import java.io.File;

import javax.ws.rs.*;
import javax.ws.rs.core.*;

import org.ruleml.psoa.psoatransrun.PSOATransRunException;
import org.ruleml.psoa.psoatransrun.engine.ExecutionEngine;
import org.ruleml.psoa.psoatransrun.prolog.XSBEngine;
import org.ruleml.psoa.psoatransrun.restful.models.ExecutionRequest;
import org.ruleml.psoa.psoatransrun.tptp.VampirePrimeEngine;


@Path("/execute")
public class ExecutionResource
{
	private static XSBEngine.Config s_xsbConfig;
	private static VampirePrimeEngine.Config s_vpConfig;
	
	@POST
	@Consumes({ MediaType.APPLICATION_JSON })
	@Produces(MediaType.TEXT_PLAIN)
	@Encoded
	public String getExecutionResults(ExecutionRequest request)
	{
		String engineName = request.getEngine();
		ExecutionEngine engine;
		
		if (engineName.equalsIgnoreCase("xsb"))
			engine = createXSBEngine();
		else if (engineName.equalsIgnoreCase("vp"))
			engine = createVPEngine();
		else
			throw new PSOATransRunException("Unknown engine: " + engineName);
		
		return engine.executeQuery(request.getKB(), request.getQuery(), request.getQueryVars()).toString();
	}
	
	private XSBEngine createXSBEngine()
	{
		if (s_xsbConfig == null)
		{
			s_xsbConfig = new XSBEngine.Config();
			File xsbfolder = new File(System.getProperty("user.home"), "git/psoa.git/lib/XSB");
			
			s_xsbConfig.xsbFolderPath = xsbfolder.getAbsolutePath();
//			s_xsbConfig.xsbFolderPath = "D:\\Software\\Development\\XSBProlog";
		}
		return new XSBEngine(s_xsbConfig);
	}
	
	private VampirePrimeEngine createVPEngine()
	{
		if (s_vpConfig == null)
		{
			s_vpConfig = new VampirePrimeEngine.Config();
		}
		
		return new VampirePrimeEngine(s_vpConfig);
	}
}