//+------------------------------------------------------------------+
//|                                                   JASONNode.mqh  |
//|                        Minimal JSON Parser for MQL5              |
//|                        For use with GoldMind AI EA               |
//+------------------------------------------------------------------+
#property copyright "GoldMind AI"
#property strict

//+------------------------------------------------------------------+
//| JSON Node Types                                                   |
//+------------------------------------------------------------------+
enum ENUM_JSON_TYPE
{
   JSON_NULL,
   JSON_BOOL,
   JSON_NUMBER,
   JSON_STRING,
   JSON_ARRAY,
   JSON_OBJECT
};

//+------------------------------------------------------------------+
//| JSON Node class                                                   |
//+------------------------------------------------------------------+
class JASONNode
{
private:
   ENUM_JSON_TYPE    m_type;
   string            m_key;
   string            m_strValue;
   double            m_numValue;
   bool              m_boolValue;
   JASONNode*        m_children[];
   int               m_childCount;

   void              SkipWhitespace(const string &json, int &pos);
   JASONNode*        ParseValue(const string &json, int &pos);
   JASONNode*        ParseObject(const string &json, int &pos);
   JASONNode*        ParseArray(const string &json, int &pos);
   string            ParseString(const string &json, int &pos);
   double            ParseNumber(const string &json, int &pos);
   bool              ParseBool(const string &json, int &pos);
   void              ParseNull(const string &json, int &pos);

public:
                     JASONNode();
                    ~JASONNode();

   // Deserialize a JSON string into this node
   bool              Deserialize(const string &json);

   // Accessors
   ENUM_JSON_TYPE    GetType()          { return m_type; }
   string            GetKey()           { return m_key; }
   void              SetKey(string key) { m_key = key; }
   string            GetString()        { return m_strValue; }
   double            GetDouble()        { return m_numValue; }
   int               GetInt()           { return (int)m_numValue; }
   bool              GetBool()          { return m_boolValue; }
   int               ChildCount()       { return m_childCount; }
   JASONNode*        GetChild(int i)    { if(i >= 0 && i < m_childCount) return m_children[i]; return NULL; }

   // Find a child by key (for objects)
   JASONNode*        FindKey(const string &key);

   // Convenience: get typed values from a nested path like "order.type"
   string            GetStringByKey(const string &key);
   double            GetDoubleByKey(const string &key);
   int               GetIntByKey(const string &key);
   bool              GetBoolByKey(const string &key);

   // Clear and free children
   void              Clear();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
JASONNode::JASONNode()
{
   m_type       = JSON_NULL;
   m_key        = "";
   m_strValue   = "";
   m_numValue   = 0;
   m_boolValue  = false;
   m_childCount = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
JASONNode::~JASONNode()
{
   Clear();
}

//+------------------------------------------------------------------+
//| Clear all children                                                |
//+------------------------------------------------------------------+
void JASONNode::Clear()
{
   for(int i = 0; i < m_childCount; i++)
   {
      if(m_children[i] != NULL)
      {
         delete m_children[i];
         m_children[i] = NULL;
      }
   }
   ArrayResize(m_children, 0);
   m_childCount = 0;
}

//+------------------------------------------------------------------+
//| Deserialize JSON string                                           |
//+------------------------------------------------------------------+
bool JASONNode::Deserialize(const string &json)
{
   Clear();
   int pos = 0;
   SkipWhitespace(json, pos);

   if(pos >= StringLen(json))
      return false;

   ushort ch = StringGetCharacter(json, pos);
   if(ch == '{')
   {
      JASONNode *obj = ParseObject(json, pos);
      if(obj == NULL) return false;
      // Copy obj contents into this node
      m_type       = obj.m_type;
      m_strValue   = obj.m_strValue;
      m_numValue   = obj.m_numValue;
      m_boolValue  = obj.m_boolValue;
      m_childCount = obj.m_childCount;
      ArrayResize(m_children, m_childCount);
      for(int i = 0; i < m_childCount; i++)
      {
         m_children[i]      = obj.m_children[i];
         obj.m_children[i]  = NULL; // prevent double-free
      }
      obj.m_childCount = 0;
      ArrayResize(obj.m_children, 0);
      delete obj;
      return true;
   }
   else if(ch == '[')
   {
      JASONNode *arr = ParseArray(json, pos);
      if(arr == NULL) return false;
      m_type       = arr.m_type;
      m_childCount = arr.m_childCount;
      ArrayResize(m_children, m_childCount);
      for(int i = 0; i < m_childCount; i++)
      {
         m_children[i]      = arr.m_children[i];
         arr.m_children[i]  = NULL;
      }
      arr.m_childCount = 0;
      ArrayResize(arr.m_children, 0);
      delete arr;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Skip whitespace                                                   |
//+------------------------------------------------------------------+
void JASONNode::SkipWhitespace(const string &json, int &pos)
{
   int len = StringLen(json);
   while(pos < len)
   {
      ushort ch = StringGetCharacter(json, pos);
      if(ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r')
         pos++;
      else
         break;
   }
}

//+------------------------------------------------------------------+
//| Parse a JSON value                                                |
//+------------------------------------------------------------------+
JASONNode* JASONNode::ParseValue(const string &json, int &pos)
{
   SkipWhitespace(json, pos);
   if(pos >= StringLen(json)) return NULL;

   ushort ch = StringGetCharacter(json, pos);

   if(ch == '{')
      return ParseObject(json, pos);
   if(ch == '[')
      return ParseArray(json, pos);
   if(ch == '"')
   {
      JASONNode *node = new JASONNode();
      node.m_type     = JSON_STRING;
      node.m_strValue = ParseString(json, pos);
      return node;
   }
   if(ch == 't' || ch == 'f')
   {
      JASONNode *node  = new JASONNode();
      node.m_type      = JSON_BOOL;
      node.m_boolValue = ParseBool(json, pos);
      return node;
   }
   if(ch == 'n')
   {
      JASONNode *node = new JASONNode();
      node.m_type     = JSON_NULL;
      ParseNull(json, pos);
      return node;
   }
   if(ch == '-' || (ch >= '0' && ch <= '9'))
   {
      JASONNode *node  = new JASONNode();
      node.m_type      = JSON_NUMBER;
      node.m_numValue  = ParseNumber(json, pos);
      return node;
   }
   return NULL;
}

//+------------------------------------------------------------------+
//| Parse JSON object                                                 |
//+------------------------------------------------------------------+
JASONNode* JASONNode::ParseObject(const string &json, int &pos)
{
   JASONNode *node = new JASONNode();
   node.m_type = JSON_OBJECT;
   pos++; // skip '{'

   SkipWhitespace(json, pos);
   if(pos < StringLen(json) && StringGetCharacter(json, pos) == '}')
   {
      pos++;
      return node;
   }

   while(pos < StringLen(json))
   {
      SkipWhitespace(json, pos);
      if(pos >= StringLen(json)) break;

      // Parse key
      string key = ParseString(json, pos);

      SkipWhitespace(json, pos);
      if(pos >= StringLen(json) || StringGetCharacter(json, pos) != ':')
      {
         delete node;
         return NULL;
      }
      pos++; // skip ':'

      // Parse value
      JASONNode *child = ParseValue(json, pos);
      if(child == NULL)
      {
         delete node;
         return NULL;
      }
      child.m_key = key;

      // Add child
      node.m_childCount++;
      ArrayResize(node.m_children, node.m_childCount);
      node.m_children[node.m_childCount - 1] = child;

      SkipWhitespace(json, pos);
      if(pos >= StringLen(json)) break;

      ushort ch = StringGetCharacter(json, pos);
      if(ch == '}')
      {
         pos++;
         return node;
      }
      if(ch == ',')
         pos++;
   }
   return node;
}

//+------------------------------------------------------------------+
//| Parse JSON array                                                  |
//+------------------------------------------------------------------+
JASONNode* JASONNode::ParseArray(const string &json, int &pos)
{
   JASONNode *node = new JASONNode();
   node.m_type = JSON_ARRAY;
   pos++; // skip '['

   SkipWhitespace(json, pos);
   if(pos < StringLen(json) && StringGetCharacter(json, pos) == ']')
   {
      pos++;
      return node;
   }

   while(pos < StringLen(json))
   {
      JASONNode *child = ParseValue(json, pos);
      if(child == NULL)
      {
         delete node;
         return NULL;
      }

      node.m_childCount++;
      ArrayResize(node.m_children, node.m_childCount);
      node.m_children[node.m_childCount - 1] = child;

      SkipWhitespace(json, pos);
      if(pos >= StringLen(json)) break;

      ushort ch = StringGetCharacter(json, pos);
      if(ch == ']')
      {
         pos++;
         return node;
      }
      if(ch == ',')
         pos++;
   }
   return node;
}

//+------------------------------------------------------------------+
//| Parse string (expects opening quote at pos)                       |
//+------------------------------------------------------------------+
string JASONNode::ParseString(const string &json, int &pos)
{
   if(pos >= StringLen(json) || StringGetCharacter(json, pos) != '"')
      return "";
   pos++; // skip opening quote

   string result = "";
   while(pos < StringLen(json))
   {
      ushort ch = StringGetCharacter(json, pos);
      if(ch == '\\')
      {
         pos++;
         if(pos < StringLen(json))
         {
            ushort esc = StringGetCharacter(json, pos);
            if(esc == '"')       result += "\"";
            else if(esc == '\\') result += "\\";
            else if(esc == '/')  result += "/";
            else if(esc == 'n')  result += "\n";
            else if(esc == 'r')  result += "\r";
            else if(esc == 't')  result += "\t";
            else                 { result += "\\"; result += ShortToString(esc); }
            pos++;
         }
      }
      else if(ch == '"')
      {
         pos++; // skip closing quote
         return result;
      }
      else
      {
         result += ShortToString(ch);
         pos++;
      }
   }
   return result;
}

//+------------------------------------------------------------------+
//| Parse number                                                      |
//+------------------------------------------------------------------+
double JASONNode::ParseNumber(const string &json, int &pos)
{
   int start = pos;
   int len   = StringLen(json);

   // optional minus
   if(pos < len && StringGetCharacter(json, pos) == '-')
      pos++;

   // digits
   while(pos < len)
   {
      ushort ch = StringGetCharacter(json, pos);
      if(ch >= '0' && ch <= '9')
         pos++;
      else
         break;
   }

   // decimal
   if(pos < len && StringGetCharacter(json, pos) == '.')
   {
      pos++;
      while(pos < len)
      {
         ushort ch = StringGetCharacter(json, pos);
         if(ch >= '0' && ch <= '9')
            pos++;
         else
            break;
      }
   }

   // exponent
   if(pos < len)
   {
      ushort ch = StringGetCharacter(json, pos);
      if(ch == 'e' || ch == 'E')
      {
         pos++;
         if(pos < len)
         {
            ch = StringGetCharacter(json, pos);
            if(ch == '+' || ch == '-')
               pos++;
         }
         while(pos < len)
         {
            ch = StringGetCharacter(json, pos);
            if(ch >= '0' && ch <= '9')
               pos++;
            else
               break;
         }
      }
   }

   string numStr = StringSubstr(json, start, pos - start);
   return StringToDouble(numStr);
}

//+------------------------------------------------------------------+
//| Parse boolean                                                     |
//+------------------------------------------------------------------+
bool JASONNode::ParseBool(const string &json, int &pos)
{
   if(StringSubstr(json, pos, 4) == "true")
   {
      pos += 4;
      return true;
   }
   if(StringSubstr(json, pos, 5) == "false")
   {
      pos += 5;
      return false;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Parse null                                                        |
//+------------------------------------------------------------------+
void JASONNode::ParseNull(const string &json, int &pos)
{
   if(StringSubstr(json, pos, 4) == "null")
      pos += 4;
}

//+------------------------------------------------------------------+
//| Find child by key                                                 |
//+------------------------------------------------------------------+
JASONNode* JASONNode::FindKey(const string &key)
{
   if(m_type != JSON_OBJECT)
      return NULL;
   for(int i = 0; i < m_childCount; i++)
   {
      if(m_children[i] != NULL && m_children[i].m_key == key)
         return m_children[i];
   }
   return NULL;
}

//+------------------------------------------------------------------+
//| Get string value by key                                           |
//+------------------------------------------------------------------+
string JASONNode::GetStringByKey(const string &key)
{
   JASONNode *node = FindKey(key);
   if(node != NULL) return node.GetString();
   return "";
}

//+------------------------------------------------------------------+
//| Get double value by key                                           |
//+------------------------------------------------------------------+
double JASONNode::GetDoubleByKey(const string &key)
{
   JASONNode *node = FindKey(key);
   if(node != NULL) return node.GetDouble();
   return 0.0;
}

//+------------------------------------------------------------------+
//| Get int value by key                                              |
//+------------------------------------------------------------------+
int JASONNode::GetIntByKey(const string &key)
{
   JASONNode *node = FindKey(key);
   if(node != NULL) return node.GetInt();
   return 0;
}

//+------------------------------------------------------------------+
//| Get bool value by key                                             |
//+------------------------------------------------------------------+
bool JASONNode::GetBoolByKey(const string &key)
{
   JASONNode *node = FindKey(key);
   if(node != NULL) return node.GetBool();
   return false;
}
//+------------------------------------------------------------------+
