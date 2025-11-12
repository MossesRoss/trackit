/**
 * @file WeeklyReport.gs
 * @version 2.0.0 (Library-Free)
 * This script runs weekly, fetches user data from Firebase,
 * generates a report, gets AI insights, and emails it to the user.
 * This version removes all external libraries and uses manual JWT
 * creation for Firebase authentication.
 */

// --- GLOBAL CONFIGURATION ---

// Get script properties set by the user in Project Settings
const SCRIPT_PROPERTIES = PropertiesService.getScriptProperties();
const AI_SCRIPT_URL = SCRIPT_PROPERTIES.getProperty('AI_SCRIPT_URL');
const GEMINI_API_KEY = SCRIPT_PROPERTIES.getProperty('GEMINI_API_KEY'); // <-- We'll use this from your properties now
const PROJECT_ID = SCRIPT_PROPERTIES.getProperty('PROJECT_ID');
const SERVICE_ACCOUNT_CREDS = JSON.parse(SCRIPT_PROPERTIES.getProperty('SERVICE_ACCOUNT_CREDS') || '{}');

// The base URL for Firestore REST API
const FIRESTORE_BASE_URL = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

// ==================================================================
//
//               PRIMARY TRIGGER & SETUP FUNCTIONS
//
// ==================================================================

/**
 * ONE-TIME SETUP FUNCTION
 * Deletes any old triggers and creates a new one to run every Monday.
 *
 * @public
 */
function createWeeklyTrigger() {
  const triggerFunctionName = 'runWeeklyReport';

  // 1. Delete all existing triggers for this function to avoid duplicates
  const allTriggers = ScriptApp.getProjectTriggers();
  for (const trigger of allTriggers) {
    if (trigger.getHandlerFunction() === triggerFunctionName) {
      ScriptApp.deleteTrigger(trigger);
      console.log(`Deleted existing trigger: ${trigger.getUniqueId()}`);
    }
  }

  // 2. Create the new weekly trigger
  ScriptApp.newTrigger(triggerFunctionName)
    .timeBased()
    .onWeekDay(ScriptApp.WeekDay.MONDAY)
    .atHour(9) // 9:00 AM in your project's time zone (Asia/Kolkata)
    .create();

  console.log(`Successfully created new weekly trigger for ${triggerFunctionName}.`);
  // Note: The first run will require authorization.
}

/**
 * MAIN FUNCTION (Triggered weekly)
 * Fetches all users and runs the report for each one.
 *
 * @public
 */
function runWeeklyReport() {
  console.log('--- Starting Weekly Report Job ---');
  try {
    const authToken = getFirebaseServiceAccountToken_();
    if (!authToken) {
      console.error("Failed to get auth token. Aborting job.");
      return;
    }

    const allUsers = getAllUsers_(authToken);
    console.log(`Found ${allUsers.length} users to process.`);

    for (const user of allUsers) {
      const email = user.email;
      const userId = user.userId;

      if (!email) {
        console.warn(`User ${userId} has no email. Skipping.`);
        continue;
      }

      console.log(`Processing report for user: ${email} (${userId})`);
      processUserReport_(userId, email, authToken);
    }
    console.log('--- Weekly Report Job Finished ---');
  } catch (e) {
    console.error(`Fatal error in runWeeklyReport: ${e.message}\n${e.stack}`);
  }
}

// ==================================================================
//
//               CORE REPORT PROCESSING LOGIC
//
// ==================================================================

/**
 * Fetches data, builds the report, and emails it for a *single* user.
 *
 * @param {string} userId The user's Firebase UID.
 * @param {string} email The user's email address.
 * @param {string} authToken A valid Firebase auth token.
 * @private
 */
function processUserReport_(userId, email, authToken) {
  try {
    // 1. Get all active and archived goals for the user
    const allGoals = getAllGoalsForUser_(userId, authToken);
    const activeGoal = allGoals.find(g => g.status === 'active');
    
    if (!activeGoal) {
      console.log(`User ${email} has no active goal. Skipping.`);
      return;
    }

    // 2. Calculate stats
    const stats = calculateAllStats_(activeGoal);

    // 3. Get AI-powered insights (Projection & Planning)
    const aiInsights = getAiInsights_(activeGoal, stats, userId, authToken);

    // 4. Generate the email content
    const emailSubject = `Your Weekly Goal Report: ${activeGoal.title}`;
    const emailBody = buildHtmlEmail_(activeGoal, stats, aiInsights, email);

    // 5. Send the email
    MailApp.sendEmail({
      to: email,
      subject: emailSubject,
      htmlBody: emailBody,
      name: 'TrackIt Weekly Bot'
    });

    console.log(`Successfully processed and sent report to ${email}.`);

  } catch (e) {
    console.error(`Failed to process report for ${email}: ${e.message}\n${e.stack}`);
  }
}

/**
 * Fetches all active and archived goals for a specific user.
 *
 * @param {string} userId The user's Firebase UID.
 * @param {string} authToken A valid Firebase auth token.
 * @return {Array<Object>} A list of goal objects.
 * @private
 */
function getAllGoalsForUser_(userId, authToken) {
  const firestoreUrl = `${FIRESTORE_BASE_URL}/users/${userId}/goals`;
  const options = {
    method: 'get',
    headers: { 'Authorization': 'Bearer ' + authToken },
    contentType: 'application/json',
    muteHttpExceptions: true
  };

  const response = UrlFetchApp.fetch(firestoreUrl, options);
  const json = JSON.parse(response.getContentText());

  if (!json.documents) {
    console.log(`No goals found for user ${userId}.`);
    return [];
  }

  // Convert Firestore document format to clean JS objects
  return json.documents.map(doc => firestoreDocToJsObject_(doc));
}

/**
 * Calls the AI script to get projection, next week's plan, and last week's review.
 *
 * @param {Object} activeGoal The user's active goal.
 * @param {Object} stats The calculated stats.
 * @param {string} userId The user's ID (for saving/fetching plans).
 * @param {string} authToken A valid Firebase auth token.
 * @return {Object} An object with `projection`, `nextWeekPlan`, and `lastWeekReview`.
 * @private
 */
function getAiInsights_(activeGoal, stats, userId, authToken) {
  const insights = {
    projection: "No projection available.",
    nextWeekPlan: "No plan available.",
    lastWeekReview: "No data from last week to review."
  };

  try {
    // 1. Get projection (Point 3.4)
    const projectionPayload = {
      action: 'getWeeklyProjection',
      apiKey: GEMINI_API_KEY,
      goal: activeGoal,
      stats: stats
    };
    insights.projection = callAiScript_(projectionPayload);

    // 2. Get last week's plan (Point 7)
    const lastWeekPlan = fetchLastWeeksPlan_(userId, authToken);
    if (lastWeekPlan) {
      const reviewPayload = {
        action: 'reviewLastWeekPlan',
        apiKey: GEMINI_API_KEY,
        goal: activeGoal,
        plan: lastWeekPlan
      };
      insights.lastWeekReview = callAiScript_(reviewPayload);
    }

    // 3. Get next week's plan (Point 6)
    const nextPlanPayload = {
      action: 'generateNextWeekPlan',
      apiKey: GEMINI_API_KEY,
      goal: activeGoal
    };
    insights.nextWeekPlan = callAiScript_(nextPlanPayload);

    // 4. Save the new plan for next week's review
    saveWeeklyPlan_(userId, insights.nextWeekPlan, authToken);

  } catch (e) {
    console.error(`Failed to get AI insights: ${e.message}`);
  }
  return insights;
}

/**
 * Calculates all the required stats for the report.
 *
 * @param {Object} goal The user's active goal.
 * @return {Object} An object containing all stats.
 * @private
 */
function calculateAllStats_(goal) {
  const now = new Date();
  const oneWeekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const goalStartDate = new Date(goal.createdAt);
  
  let totalHoursThisWeek = 0;
  let totalHoursOverall = 0;
  let milestonesCompletedThisWeek = 0;
  const dailyHours = {}; // For graph 3.5.1
  const weeklyMilestones = {}; // For graph 3.5.2

  // 1. Calculate week number (Point 3.1)
  const msPerWeek = 7 * 24 * 60 * 60 * 1000;
  const weeksSinceStart = Math.ceil((now.getTime() - goalStartDate.getTime()) / msPerWeek);
  
  for (const milestone of goal.milestones) {
    // 2. Calculate time logs (Points 3.2, 3.5.1)
    if (milestone.timeLog) {
      for (const session of milestone.timeLog) {
        const sessionDate = new Date(session.timestamp);
        const hours = (session.durationInSeconds || 0) / 3600;
        
        totalHoursOverall += hours;
        
        // Check if session was in the last 7 days
        if (sessionDate > oneWeekAgo) {
          totalHoursThisWeek += hours;
          
          // For graph (3.5.1): Store by day (e.g., "Oct 28")
          const dayKey = sessionDate.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
          dailyHours[dayKey] = (dailyHours[dayKey] || 0) + hours;
        }
      }
    }
    
    // 3. Calculate milestone completions (Point 3.5.2)
    if (milestone.completedAt) {
      const completedDate = new Date(milestone.completedAt);
      
      // For graph (3.5.2): Store by week number
      const weekNum = Math.ceil((completedDate.getTime() - goalStartDate.getTime()) / msPerWeek);
      const weekKey = `Week ${weekNum}`;
      weeklyMilestones[weekKey] = (weeklyMilestones[weekKey] || 0) + 1;
      
      if (completedDate > oneWeekAgo) {
        milestonesCompletedThisWeek++;
      }
    }
  }

  // 4. Calculate average hours per week (Point 3.3)
  const avgHoursPerWeek = weeksSinceStart > 0 ? (totalHoursOverall / weeksSinceStart) : totalHoursOverall;

  return {
    weekNumber: weeksSinceStart,
    totalHoursThisWeek: totalHoursThisWeek,
    avgHoursPerWeek: avgHoursPerWeek,
    totalHoursOverall: totalHoursOverall,
    dailyHoursGraph: dailyHours,         // Data for graph 3.5.1
    weeklyMilestonesGraph: weeklyMilestones, // Data for graph 3.5.2
  };
}


// ==================================================================
//
//               NEW AUTHENTICATION FUNCTIONS (NO LIBRARY)
//
// ==================================================================

/**
 * Creates a JWT and exchanges it for a Firebase Scoped Access Token.
 *
 * @return {string|null} The access token, or null on failure.
 * @private
 */
function getFirebaseServiceAccountToken_() {
  const service = SERVICE_ACCOUNT_CREDS;
  if (!service || !service.private_key || !service.client_email) {
    console.error("SERVICE_ACCOUNT_CREDS property is missing or invalid.");
    return null;
  }
  
  const privateKey = service.private_key;
  const clientEmail = service.client_email;
  const tokenUri = service.token_uri;

  // 1. Create the JWT header
  const header = {
    alg: 'RS256',
    typ: 'JWT'
  };

  // 2. Create the JWT claim set
  const now = Math.floor(Date.now() / 1000);
  const claimSet = {
    iss: clientEmail,
    scope: 'https://www.googleapis.com/auth/datastore', // Firestore scope
    aud: tokenUri,
    exp: now + 3600, // Token expires in 1 hour
    iat: now
  };

  // 3. Sign the JWT
  const jwtSignatureInput = `${base64URLEncode_(JSON.stringify(header))}.${base64URLEncode_(JSON.stringify(claimSet))}`;
  const signature = Utilities.computeRsaSha256Signature(jwtSignatureInput, privateKey);
  const jwt = `${jwtSignatureInput}.${base64URLEncode_(signature)}`;

  // 4. Exchange the JWT for an Access Token
  const response = UrlFetchApp.fetch(tokenUri, {
    method: 'post',
    contentType: 'application/x-www-form-urlencoded',
    payload: {
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt
    },
    muteHttpExceptions: true
  });

  const data = JSON.parse(response.getContentText());
  if (data.access_token) {
    return data.access_token;
  } else {
    console.error(`Token exchange failed: ${JSON.stringify(data)}`);
    return null;
  }
}

/**
 * Helper to Base64 URL-encode a string or byte array.
 *
 * @param {string|Array<byte>} input The data to encode.
 * @return {string} The Base64 URL-encoded string.
 * @private
 */
function base64URLEncode_(input) {
  const base64 = typeof input === 'string'
    ? Utilities.base64Encode(input, Utilities.Charset.UTF_8)
    : Utilities.base64Encode(input);
  
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}


// ==================================================================
//
//               HELPER & UTILITY FUNCTIONS
//
// ==================================================================

/**
 * Fetches all users from the /users collection to find their emails.
 *
 * @param {string} authToken A valid Firebase auth token.
 * @return {Array<Object>} A list of user objects { userId, email }.
 * @private
 */
function getAllUsers_(authToken) {
  const firestoreUrl = `${FIRESTORE_BASE_URL}/users`;
  const options = {
    method: 'get',
    headers: { 'Authorization': 'Bearer ' + authToken },
    contentType: 'application/json',
    muteHttpExceptions: true
  };

  const response = UrlFetchApp.fetch(firestoreUrl, options);
  const json = JSON.parse(response.getContentText());

  if (!json.documents) {
    console.warn("Could not fetch user list or no users found.");
    return [];
  }

  return json.documents.map(doc => {
    const userId = doc.name.split('/').pop();
    const email = doc.fields && doc.fields.email ? doc.fields.email.stringValue : null;
    return { userId, email };
  });
}

/**
 * Saves the newly generated plan to Firestore for next week's review.
 *
 * @param {string} userId The user's Firebase UID.
 * @param {string} planText The text of the generated plan.
 * @param {string} authToken A valid Firebase auth token.
 * @private
 */
function saveWeeklyPlan_(userId, planText, authToken) {
  // We'll use the week number as the document ID
  const weekKey = `week_${new Date().getFullYear()}_${getWeekNumber_(new Date())}`;
  const firestoreUrl = `${FIRESTORE_BASE_URL}/users/${userId}/weekly_plans/${weekKey}`;

  const payload = {
    fields: {
      plan: { stringValue: planText },
      createdAt: { timestampValue: new Date().toISOString() }
    }
  };

  const options = {
    method: 'patch', // 'patch' will create or overwrite
    headers: { 'Authorization': 'Bearer ' + authToken },
    contentType: 'application/json',
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  };

  UrlFetchApp.fetch(firestoreUrl, options);
  console.log(`Saved plan for ${userId} for ${weekKey}.`);
}

/**
 * Fetches the plan generated *last* week.
 *
 * @param {string} userId The user's Firebase UID.
 * @param {string} authToken A valid Firebase auth token.
 * @return {string|null} The text of last week's plan, or null.
 * @private
 */
function fetchLastWeeksPlan_(userId, authToken) {
  const lastWeek = new Date(new Date().getTime() - 7 * 24 * 60 * 60 * 1000);
  const weekKey = `week_${lastWeek.getFullYear()}_${getWeekNumber_(lastWeek)}`;
  
  const firestoreUrl = `${FIRESTORE_BASE_URL}/users/${userId}/weekly_plans/${weekKey}`;

  const options = {
    method: 'get',
    headers: { 'Authorization': 'Bearer ' + authToken },
    contentType: 'application/json',
    muteHttpExceptions: true
  };

  const response = UrlFetchApp.fetch(firestoreUrl, options);
  if (response.getResponseCode() !== 200) {
    console.log(`No plan found from last week (${weekKey}) for user ${userId}.`);
    return null;
  }
  
  const json = JSON.parse(response.getContentText());
  return json.fields && json.fields.plan ? json.fields.plan.stringValue : null;
}

/**
 * Gets the ISO week number for a given date.
 *
 * @param {Date} d The date.
 * @return {number} The ISO week number.
 * @private
 */
function getWeekNumber_(d) {
  d = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
  return weekNo;
}

/**
 * Calls the AI Apps Script (the one your app uses) with a specific action.
 *
 * @param {Object} payload The data to send (must include 'action' and 'apiKey').
 * @return {string} The 'suggestion' from the AI, or a fallback string.
 * @private
 */
function callAiScript_(payload) {
  if (!AI_SCRIPT_URL) {
    return "AI Script URL not configured.";
  }
  
  try {
    const options = {
      method: 'post',
      contentType: 'application/json',
      payload: JSON.stringify(payload),
      muteHttpExceptions: true
    };

    const response = UrlFetchApp.fetch(AI_SCRIPT_URL, options);
    const data = JSON.parse(response.getContentText());

    if (data.suggestion) {
      return data.suggestion;
    }
    if (data.error) {
      console.error(`AI Script Error: ${data.error}`);
      return `AI Error: ${data.error}`;
    }
    return "AI script returned an unknown response.";
    
  } catch (e) {
    console.error(`Failed to call AI script: ${e.message}`);
    return `Failed to connect to AI script: ${e.message}`;
  }
}

/**
 * Converts a Firestore document into a simpler JS object.
 *
 * @param {Object} doc The Firestore document.
 * @return {Object} A clean JS object.
 * @private
 */
function firestoreDocToJsObject_(doc) {
  const obj = {};
  if (!doc.fields) return obj;

  for (const key in doc.fields) {
    const field = doc.fields[key];
    if (field.stringValue) obj[key] = field.stringValue;
    else if (field.integerValue) obj[key] = parseInt(field.integerValue, 10);
    else if (field.doubleValue) obj[key] = field.doubleValue;
    else if (field.booleanValue) obj[key] = field.booleanValue;
    else if (field.timestampValue) obj[key] = field.timestampValue;
    else if (field.nullValue === null) obj[key] = null;
    else if (field.arrayValue) {
      obj[key] = (field.arrayValue.values || []).map(v => mapFirestoreValue_(v));
    }
    else if (field.mapValue) {
      obj[key] = firestoreDocToJsObject_(field.mapValue); // Recursively map
    }
  }
  // Add special fields
  obj.id = doc.name.split('/').pop(); // Add the doc ID
  if (doc.createTime) obj.createTime = doc.createTime;
  if (doc.updateTime) obj.updateTime = doc.updateTime;
  
  // Specific fix for goal status (which is an index)
  if (key === 'status' && obj.status) {
      obj.status = ['active', 'achieved', 'givenUp'][obj.status] || 'active';
  }

  return obj;
}

/**
 * Recursive helper for firestoreDocToJsObject_ to map values inside arrays.
 *
 * @param {Object} field The Firestore value object.
 * @return {*} The simple JS value.
 * @private
 */
function mapFirestoreValue_(field) {
  if (field.stringValue) return field.stringValue;
  if (field.integerValue) return parseInt(field.integerValue, 10);
  if (field.doubleValue) return field.doubleValue;
  if (field.booleanValue) return field.booleanValue;
  if (field.timestampValue) return field.timestampValue;
  if (field.nullValue === null) return null;
  if (field.arrayValue) return (field.arrayValue.values || []).map(v => mapFirestoreValue_(v));
  if (field.mapValue) return firestoreDocToJsObject_({ fields: field.mapValue.fields || {} });
  return null;
}

// ==================================================================
//
//               HTML EMAIL GENERATION
//
// ==================================================================

/**
 * Builds the HTML for the weekly report email.
 *
 * @param {Object} goal The active goal.
 * @param {Object} stats The calculated stats.
 * @param {Object} aiInsights The AI-generated text.
 * @param {string} email The user's email (for greeting).
 * @return {string} The full HTML string for the email body.
 * @private
 */
function buildHtmlEmail_(goal, stats, aiInsights, email) {
  const username = email.split('@')[0];
  
  // Create simple bar charts
  const dailyGraphHtml = generateBarChartHtml_(stats.dailyHoursGraph, "Hours");
  const weeklyGraphHtml = generateBarChartHtml_(stats.weeklyMilestonesGraph, "Milestones");
  
  // Format AI text (replace newlines with <br>)
  const projection = aiInsights.projection.replace(/\n/g, '<br>');
  const lastWeekReview = aiInsights.lastWeekReview.replace(/\n/g, '<br>');
  const nextWeekPlan = aiInsights.nextWeekPlan.replace(/\n/g, '<br>');

  return `
  <html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Your Weekly Report</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; margin: 0; padding: 0; background-color: #f4f7f6; }
      .container { width: 90%; max-width: 600px; margin: 20px auto; background-color: #ffffff; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.05); overflow: hidden; }
      .header { background-color: #4A90E2; padding: 30px; text-align: center; }
      .header h1 { margin: 0; color: #ffffff; font-size: 24px; }
      .content { padding: 30px; }
      .greeting { font-size: 18px; color: #333; margin-bottom: 20px; }
      .section { margin-bottom: 25px; padding-bottom: 20px; border-bottom: 1px solid #eeeeee; }
      .section-last { margin-bottom: 0; border-bottom: none; }
      .section h2 { font-size: 20px; color: #4A90E2; margin-top: 0; margin-bottom: 15px; }
      .stats-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; }
      .stat-box { background-color: #f9f9f9; border-radius: 6px; padding: 15px; text-align: center; }
      .stat-box .value { font-size: 28px; font-weight: 600; color: #4A90E2; margin: 0 0 5px 0; }
      .stat-box .label { font-size: 14px; color: #555; margin: 0; }
      .ai-box { background-color: #fdfdfd; border: 1px solid #e9e9e9; border-radius: 6px; padding: 20px; font-size: 15px; line-height: 1.6; color: #333; }
      .footer { background-color: #f9f9f9; padding: 20px 30px; text-align: center; font-size: 12px; color: #888; }
      .chart-container { width: 100%; margin-top: 20px; }
      .chart-bar { display: flex; align-items: center; margin-bottom: 8px; font-size: 12px; }
      .bar-label { width: 80px; text-align: right; padding-right: 10px; color: #555; white-space: nowrap; }
      .bar-bg { flex: 1; background-color: #f0f0f0; border-radius: 4px; height: 20px; overflow: hidden; }
      .bar-fill { height: 100%; background-color: #4CAF50; border-radius: 4px 0 0 4px; }
      .bar-value { padding-left: 8px; color: #333; font-weight: 500; }
    </style>
  </head>
  <body>
    <div class="container">
      <div class="header">
        <h1>Your Weekly Report</h1>
      </div>
      <div class="content">
        <div class="greeting">Hi ${username},</div>
        <p>Here's your weekly progress report for your goal: <strong>${goal.title}</strong>.</p>

        <div class="section">
          <h2>Your Week at a Glance</h2>
          <div class="stats-grid">
            <div class="stat-box">
              <div class="value">${stats.weekNumber}</div>
              <div class="label">Week of Goal</div>
            </div>
            <div class="stat-box">
              <div class="value">${stats.totalHoursThisWeek.toFixed(1)}</div>
              <div class="label">Hours This Week</div>
            </div>
            <div class="stat-box">
              <div class="value">${stats.avgHoursPerWeek.toFixed(1)}</div>
              <div class="label">Avg. Hours / Week</div>
            </div>
            <div class="stat-box">
              <div class="value">${stats.totalHoursOverall.toFixed(1)}</div>
              <div class="label">Total Hours Logged</div>
            </div>
          </div>
        </div>

        <div class="section">
          <h2>AI Projection (Point 3.4)</h2>
          <div class="ai-box">${projection}</div>
        </div>

        <div class="section">
          <h2>AI Review of Last Week (Point 7)</h2>
          <div class="ai-box">${lastWeekReview}</div>
        </div>
        
        <div class="section">
          <h2>AI Plan for Next Week (Point 6)</h2>
          <div class="ai-box">${nextWeekPlan}</div>
        </div>

        <div class="section">
          <h2>Daily Hours This Week (Graph 3.5.1)</h2>
          <div class="chart-container">${dailyGraphHtml}</div>
        </div>

        <div class="section-last">
          <h2>Milestones Completed (Graph 3.5.2)</h2>
          <div class="chart-container">${weeklyGraphHtml}</div>
        </div>
        
      </div>
      <div class="footer">
        <p>Keep up the great work!</p>
        <p>&copy; ${new Date().getFullYear()} TrackIt. All rights reserved.</p>
      </div>
    </div>
  </body>
  </html>
  `;
}

/**
 * Generates simple HTML/CSS bar charts.
 *
 * @param {Object} data A map of { label: value }.
 * @param {string} unit The unit for the value (e.g., "Hours", "Milestones").
 * @return {string} The HTML for the bar chart.
 * @private
 */
function generateBarChartHtml_(data, unit) {
  if (Object.keys(data).length === 0) {
    return "<p>No data to display for this period.</p>";
  }
  
  let html = "";
  let maxValue = 0;
  for (const key in data) {
    if (data[key] > maxValue) maxValue = data[key];
  }

  // Ensure maxValue is at least 1 to avoid division by zero
  maxValue = Math.max(maxValue, 1);

  for (const key in data) {
    const value = data[key];
    const percentage = (value / maxValue) * 100;
    const displayValue = unit === 'Hours' ? value.toFixed(1) : value;

    html += `
    <div class="chart-bar">
      <div class="bar-label">${key}</div>
      <div class="bar-bg">
        <div class="bar-fill" style="width: ${percentage}%;"></div>
      </div>
      <div class="bar-value">${displayValue} ${unit}</div>
    </div>
    `;
  }
  return html;
}
