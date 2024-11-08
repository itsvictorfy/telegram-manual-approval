#!/bin/bash

# Setup

TELEGRAM_KEY=""
TELEGRAM_CHAT_ID=""
UPDATE_REQUESTS=60
APPROVAL_TEXT="Please approve deployment"
APPROVAL_BUTTON="Approve"
REJECT_BUTTON="Reject"
APPROVED_TEXT="Approved!"
REJECTED_TEXT="Rejected!"
TIMEOUT_TEXT="Timeout!"

# Define long options
LONGOPTS=TELEGRAM_KEY:,TELEGRAM_CHAT_ID:,UPDATE_REQUESTS:,APPROVAL_TEXT:,APPROVAL_BUTTON:,REJECT_BUTTON:,APPROVED_TEXT:,REJECTED_TEXT:,TIMEOUT_TEXT:

VALID_ARGS=$(getopt --longoptions $LONGOPTS -- "$@")
if [[ $? -ne 0 ]]; then
    exit 1;
fi

# Extract the options and arguments
while true; do
  if [[ $1 == '' ]]; then
    break;
  fi
  if [[ $1 == ' ' ]]; then
    break;
  fi
  echo "$1 => $2"
  case "$1" in
    --TELEGRAM_KEY)
      TELEGRAM_KEY="$2"
      shift 2
      ;;
    --TELEGRAM_CHAT_ID)
      TELEGRAM_CHAT_ID="$2"
      shift 2
      ;;
    --UPDATE_REQUESTS)
      UPDATE_REQUESTS="$2"
      shift 2
      ;;
    --APPROVAL_TEXT)
      APPROVAL_TEXT="$2"
      shift 2
      ;;
    --APPROVAL_BUTTON)
      APPROVAL_BUTTON="$2"
      shift 2
      ;;
    --REJECT_BUTTON)
      REJECT_BUTTON="$2"
      shift 2
      ;;
    --APPROVED_TEXT)
      APPROVED_TEXT="$2"
      shift 2
      ;;
    --REJECTED_TEXT)
      REJECTED_TEXT="$2"
      shift 2
      ;;
    --TIMEOUT_TEXT)
      TIMEOUT_TEXT="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done
if [ -z "$TELEGRAM_KEY" ]; then
  echo "TELEGRAM_KEY is required"
  exit 1
fi

if [ -z "$TELEGRAM_CHAT_ID" ]; then
  echo "TELEGRAM_CHAT_ID is required"
  exit 1
fi

# Logic

generate_random_string() {
  # Количество символов в строке
  local STRING_LENGTH=12

  # Символы, из которых будет сгенерирована строка
  local CHAR_SET="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

  # Переменная для хранения итоговой строки
  local RANDOM_STRING=""

  # Используйте цикл for для выбора случайных символов из CHAR_SET
  for i in $(seq 1 $STRING_LENGTH); do
    # Выбор случайного индекса от 0 до ${#CHAR_SET}-1
    local INDEX=$((RANDOM % ${#CHAR_SET}))

    # Добавление случайного символа из CHAR_SET к RANDOM_STRING
    RANDOM_STRING="${RANDOM_STRING}${CHAR_SET:$INDEX:1}"
  done

  # Вывод сгенерированной строки
  echo "$RANDOM_STRING"
}

SESSION_ID=$(generate_random_string)
echo $"Session ID: $SESSION_ID"

MESSAGE_ID=""

sendMessage() {
  local SENT=$(curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/sendMessage" \
    --header 'Content-Type: application/json' \
    --data '{
        "chat_id": "'"$TELEGRAM_CHAT_ID"'",
        "text": "'"$APPROVAL_TEXT"'",
        "reply_markup": {
            "inline_keyboard": [
                [
                    {"text": "'"$APPROVAL_BUTTON"'", "callback_data": "a:'"$SESSION_ID"'"},
                    {"text": "'"$REJECT_BUTTON"'", "callback_data": "r:'"$SESSION_ID"'"}
                ]
            ]
        }
    }')

  # get message id without jq
  MESSAGE_ID=$(echo $SENT | awk -F '"message_id":' '{print $2}' | awk -F ',' '{print $1}')
  echo "Message ID: $MESSAGE_ID"
}

getUpdates() {
  # load data to variable
  local UPDATES=$(curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/getUpdates" \
    --header 'Content-Type: application/json' \
    --data '{
        "offset": -1,
        "timeout": 0,
        "allowed_updates": ["callback_query"]
    }')
  
  # local DEBUG_FILE="./telegram_debug.log"
  # echo "$UPDATES" >> "$DEBUG_FILE"
  # cat "$DEBUG_FILE"

  # search for a:$SESSION_ID or r:$SESSION_ID as: "data": "r:xxxxxxxxx"
  FIRST_NAME=$(echo $UPDATES | jq -r '.result[0].callback_query.from.first_name')
  LAST_NAME=$(echo $UPDATES | jq -r '.result[0].callback_query.from.last_name')
  USERNAME="${FIRST_NAME} ${LAST_NAME}"

  if [ -z "$USERNAME" ]; then
      USERNAME=$(echo $UPDATES | jq -r '.result[0].callback_query.from.username')
  fi
  local DATA=$(echo $UPDATES | awk -F '"data":' '{print $2}' | awk -F '}' '{print $1}')
  local APPROVE=$(echo $DATA | grep -o "a:$SESSION_ID")
  local REJECT=$(echo $DATA | grep -o "r:$SESSION_ID")

  if [ -z "$APPROVE" ] && [ -z "$REJECT" ]; then
    echo "0|$USERNAME"
  elif [ -n "$APPROVE" ]; then
    echo "1|$USERNAME"
  elif [ -n "$REJECT" ]; then
    echo "2|$USERNAME"
  fi
}

updateMessage() {
  local text="$1"

  curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/editMessageText" \
    --header 'Content-Type: application/json' \
    --data '{
        "chat_id": "'"$TELEGRAM_CHAT_ID"'",
        "message_id": "'"$MESSAGE_ID"'",
        "text": "'"$text"'"
    }'
}
deleteMessage() {
  curl -s --location --request POST "https://api.telegram.org/bot$TELEGRAM_KEY/deleteMessage" \
    --header 'Content-Type: application/json' \
    --data '{
        "chat_id": "'"$TELEGRAM_CHAT_ID"'",
        "message_id": "'"$MESSAGE_ID"'"
    }'
}

# Send message
sendMessage

# Wainting for approve or reject
UPDATE_REQUESTS_COUNTER=0
while true; do
  IFS='|' read -r RESULT USERNAME <<< "$(getUpdates)"
  echo "Result: $RESULT"
  echo "Username: $USERNAME"

  if [ $RESULT -eq 1 ]; then
    echo "Approved"
    echo "PUBLISH=true" >> $GITHUB_ENV
    NEWTEXT="$APPROVED_TEXT by $USERNAME"
    echo $NEWTEXT
    updateMessage "$NEWTEXT"
    exit 0
  elif [ $RESULT -eq 2 ]; then
    echo "Rejected"
    echo "PUBLISH=false" >> $GITHUB_ENV
    NEWTEXT="$REJECTED_TEXT by $USERNAME"
    echo $NEWTEXT
    updateMessage "$NEWTEXT"
    exit 0
  fi

  if [ $UPDATE_REQUESTS_COUNTER -gt $UPDATE_REQUESTS ]; then
    echo "PUBLISH=false" >> $GITHUB_ENV
    echo "Update requests limit reached"
    deleteMessage
    exit 0
  fi
  UPDATE_REQUESTS_COUNTER=$((UPDATE_REQUESTS_COUNTER + 1))
  echo "Waiting for approve or reject $UPDATE_REQUESTS_COUNTER/$UPDATE_REQUESTS"

  sleep 1
done
